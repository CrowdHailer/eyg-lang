//// What is being written, a message in a chat or a program in a shell.
////
//// A program is written as EYG text or with the structural editor, tab switches between them and both drafts are kept.
//// Text can be pasted, shift and enter starts a new line and enter sends it.
//// Text pasted into the structural editor replaces the expression in focus.

import cloud/apex/editor
import cloud/beam/execute
import cloud/shells/turn
import etui/span
import etui/style
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub type Draft {
  Message(text: String)
  Program(text: String, editor: editor.Editor, structured: Bool)
}

/// What is sent when a draft is finished.
pub type Sent {
  /// A program for a shell.
  Ran(turn.Input)
  /// A message for a chat.
  Said(String)
}

pub type Outcome {
  Edited(Draft)
  Send(Sent, Draft)
  Problem(String)
  /// The key does nothing to the draft, such as escape when nothing is being typed.
  Unhandled
}

pub fn message() -> Draft {
  Message("")
}

pub fn program() -> Draft {
  Program("", editor.new(), True)
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
          Send(
            Ran(turn.Program(program)),
            Program(..draft, editor: editor.new()),
          ),
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
    Message(text), _ -> #(typing(text, key, Message, Said), state)
    Program(text:, ..), _ -> #(
      typing(text, key, fn(text) { Program(..draft, text:) }, fn(code) {
        Ran(turn.Code(code))
      }),
      state,
    )
  }
}

fn typing(text, key, update, input) {
  case key {
    "enter" ->
      case string.trim(text) {
        "" -> Unhandled
        _ -> Send(input(text), update(""))
      }
    "shift+enter" -> Edited(update(text <> "\n"))
    "backspace" -> Edited(update(string.drop_end(text, 1)))
    "esc" -> Unhandled
    _ ->
      case string.length(key) {
        1 -> Edited(update(text <> key))
        _ -> Unhandled
      }
  }
}

/// Add pasted text to the draft.
pub fn paste(
  draft: Draft,
  text: String,
  state: execute.State,
) -> #(Outcome, execute.State) {
  let text = string.replace(text, "\r\n", "\n")
  case draft {
    Message(current) -> #(Edited(Message(current <> text)), state)
    Program(structured: False, ..) -> #(
      Edited(Program(..draft, text: draft.text <> text)),
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

/// The draft as it is shown, `active` is false while a turn is running.
pub fn lines(draft: Draft, active: Bool) -> List(span.Line) {
  case draft {
    Program(structured: True, editor: edited, ..) ->
      editor.lines(edited, active)
    Message(text) | Program(text:, ..) -> {
      let lines = string.split(text, "\n")
      let last = list.length(lines) - 1
      list.index_map(lines, fn(line, i) {
        case i == last && active {
          True ->
            span.line_new([
              span.span_plain(line),
              span.span_styled("▏", style.reversed()),
            ])
          False -> span.line_plain(line)
        }
      })
    }
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

/// Whether the editor is typing a value for an edit, when escape cancels it.
pub fn typing_value(draft: Draft) -> Bool {
  case draft {
    Program(structured: True, editor: editor.Editor(input: Some(_), ..), ..) ->
      True
    _ -> False
  }
}
