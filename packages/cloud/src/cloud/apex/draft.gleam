//// What is being written in a session, a message in a chat or a program in a shell.
////
//// Text is written in a text area, with the motions of `morph/terminal/textarea`, and program text is highlighted.
//// A program is written as EYG text or with the structural editor, tab switches between them and both drafts are kept.
//// Shift and enter starts a new line and enter sends the draft.
//// Pasted text is inserted at the cursor, in the structural editor it replaces the expression in focus.

import cloud/apex/editor
import cloud/beam/execute
import cloud/sessions/turn
import etui/span
import gleam/int
import gleam/list
import gleam/option.{None}
import morph/terminal
import morph/terminal/textarea.{type Textarea}

pub type Draft {
  Message(text: Textarea)
  Program(text: Textarea, editor: editor.Editor, structured: Bool)
}

pub type Outcome {
  Edited(Draft)
  Send(turn.Input, Draft)
  Problem(String)
  /// The key does nothing to the draft, such as escape when nothing is being typed.
  Unhandled
}

pub fn message() -> Draft {
  Message(textarea.new())
}

pub fn program() -> Draft {
  Program(textarea.new(), editor.new(), True)
}

/// Handle a key, the state is returned with modules that were looked up to check a program.
/// `files` are the files of the box, offered when importing one.
pub fn key(
  draft: Draft,
  key: String,
  state: execute.State,
  files: List(String),
) -> #(Outcome, execute.State) {
  case draft, key {
    Program(structured: True, editor: edited, ..), _
      if edited.input == None && key == "tab"
    -> #(Edited(Program(..draft, structured: False)), state)
    Program(structured: False, ..), "tab" -> #(
      Edited(Program(..draft, structured: True)),
      state,
    )
    Program(structured: True, editor: edited, ..), "enter"
      if edited.input == None
    ->
      case editor.program(edited) {
        Ok(program) -> #(
          Send(turn.Program(program), Program(..draft, editor: editor.new())),
          state,
        )
        Error(Nil) -> #(Problem("Write a program first"), state)
      }
    Program(structured: True, editor: edited, ..), "esc"
      if edited.input == None
    -> #(Unhandled, state)
    Program(structured: True, editor: edited, ..), _ -> {
      let #(edited, state) = editor.key(edited, key, state, files)
      case edited {
        Ok(edited) -> #(Edited(Program(..draft, editor: edited)), state)
        Error(reason) -> #(Problem(reason), state)
      }
    }
    Message(text), _ -> #(typing(text, key, Message, turn.Message), state)
    Program(text:, ..), _ -> #(
      typing(text, key, fn(text) { Program(..draft, text:) }, turn.Code),
      state,
    )
  }
}

fn typing(text, key, update, input) {
  case key {
    "enter" ->
      case textarea.is_empty(text) {
        True -> Unhandled
        False -> Send(input(textarea.value(text)), update(textarea.new()))
      }
    "esc" -> Unhandled
    _ ->
      case textarea.key(text, key) {
        Ok(text) -> Edited(update(text))
        Error(Nil) -> Unhandled
      }
  }
}

/// Add pasted text to the draft.
pub fn paste(
  draft: Draft,
  text: String,
  state: execute.State,
) -> #(Outcome, execute.State) {
  case draft {
    Message(current) -> #(
      Edited(Message(textarea.insert(current, text))),
      state,
    )
    Program(structured: False, ..) -> #(
      Edited(Program(..draft, text: textarea.insert(draft.text, text))),
      state,
    )
    Program(editor: edited, ..) -> {
      let #(edited, state) = editor.paste(edited, text, state)
      case edited {
        Ok(edited) -> #(Edited(Program(..draft, editor: edited)), state)
        Error(reason) -> #(Problem(reason), state)
      }
    }
  }
}

/// The lines of the draft as it is shown `width` cells wide, and the row of the cursor.
/// `active` is false while a turn is running.
pub fn lines(
  draft: Draft,
  active: Bool,
  width: Int,
) -> #(List(span.Line), Int) {
  case draft {
    Program(structured: True, editor: edited, ..) -> {
      let lines = editor.lines(edited, active)
      #(lines, int.max(0, list.length(lines) - 1))
    }
    Program(text:, ..) ->
      textarea.lines(text, terminal.highlight, width, active)
    Message(text) -> textarea.lines(text, textarea.plain, width, active)
  }
}

/// A short description of how the draft is written, for the help line.
pub fn mode(draft: Draft) -> String {
  case draft {
    Message(..) -> "message"
    Program(structured: True, ..) -> "structured"
    Program(structured: False, ..) -> "text"
  }
}
