//// The structural editor for the next command.
////
//// Keys are the same as the CLI's TUI: each key is an editing command on
//// the selected node, and some ask for a value, such as a name or a number.
//// Keys use the TUI's names, e.g. `"a"`, `"E"`, `"enter"`, `"esc"`,
//// `"left"`, `"ctrl+a"`.

import cloud/editor/combobox.{type Combobox}
import cloud/shell
import etui/widgets/input
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/ir/tree as ir
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import morph/analysis
import morph/buffer.{type Buffer}
import morph/editable as e
import morph/manipulation as m
import morph/picker
import morph/projection
import multiformats/cid/v1.{type Cid}
import touch_grass/harness/computer
import touch_grass/interface

pub type Editor {
  Editor(
    buffer: Buffer,
    mode: Mode,
    message: Option(String),
    /// Files that can be imported, from the session's file system.
    files: List(String),
  )
}

pub type Mode {
  Navigating
  EnterText(input: input.InputState, rebuild: m.Rebuild(String))
  EnterInteger(input: input.InputState, rebuild: m.Rebuild(Int))
  EnterCid(input: input.InputState, rebuild: m.Rebuild(Cid))
  Picking(box: Combobox, rebuild: m.Rebuild(String))
  Importing(box: Combobox, rebuild: m.Rebuild(ir.Reference))
}

pub type Outcome {
  Edited(Editor)
  /// Enter was pressed on a program; the editor is unchanged.
  Run(e.Expression)
}

pub fn new() -> Editor {
  Editor(buffer.empty(), Navigating, None, [])
}

/// Set the files offered when importing.
pub fn with_files(editor: Editor, files: List(String)) -> Editor {
  Editor(..editor, files:)
}

/// Edit a copy of an earlier command.
pub fn from_expression(expression: e.Expression) -> Editor {
  let buffer = buffer.from_projection(projection.all(expression))
  Editor(buffer, Navigating, None, [])
}

pub fn expression(editor: Editor) -> e.Expression {
  projection.rebuild(editor.buffer.projection)
}

pub fn is_empty(editor: Editor) -> Bool {
  expression(editor) == e.Vacant
}

/// Type information for the scope a command runs in.
pub fn context(scope: shell.Scope) -> infer.Context {
  let #(bindings, env) = analysis.env_to_tenv(scope, [])
  infer.Context(..infer.pure(), env:, level: 0, bindings:)
  |> infer.with_effects(effect_types())
}

/// The effects this shell handles, with their types.
pub fn effect_types() {
  interface.types(computer.effects())
  |> list.filter(fn(effect) { list.contains(shell.effects, effect.0) })
}

/// Type check the code if it has changed since the last check.
/// `drive` answers the references the code makes, such as imports.
pub fn check(
  editor: Editor,
  scope: shell.Scope,
  drive: fn(infer.Step(Buffer)) -> Buffer,
) -> Editor {
  case editor.buffer.analysis {
    Some(_) -> editor
    None ->
      Editor(
        ..editor,
        buffer: drive(buffer.check(editor.buffer, context(scope))),
      )
  }
}

/// Answer every reference as unavailable.
pub fn without_references(step: infer.Step(a)) -> a {
  case step {
    infer.Lookup(resume:, ..) -> without_references(resume(Error(Nil)))
    infer.Done(value) -> value
  }
}

pub fn key(editor: Editor, key: String) -> Outcome {
  // A message stays until the next key.
  let editor = Editor(..editor, message: None)
  case editor.mode {
    Navigating -> command(editor, key)
    EnterText(editing, rebuild) ->
      text_key(editor, editing, key, EnterText(_, rebuild), fn(value) {
        Ok(rebuild(value))
      })
    EnterInteger(editing, rebuild) ->
      text_key(editor, editing, key, EnterInteger(_, rebuild), fn(value) {
        case int.parse(value) {
          Ok(value) -> Ok(rebuild(value))
          Error(Nil) -> Error("Enter a valid integer")
        }
      })
    EnterCid(editing, rebuild) ->
      text_key(editor, editing, key, EnterCid(_, rebuild), fn(value) {
        let value = case value {
          "#" <> cid -> cid
          cid -> cid
        }
        case v1.from_string(value) {
          Ok(#(cid, _)) -> Ok(rebuild(cid))
          Error(_) -> Error("Enter a valid cid")
        }
      })
    Importing(box, rebuild) ->
      case combobox.update(box, key) {
        combobox.Cancelled -> Edited(Editor(..editor, mode: Navigating))
        combobox.Selected(path) ->
          Edited(
            Editor(
              ..editor,
              mode: Navigating,
              buffer: rebuild(ir.Relative(path)),
            ),
          )
        combobox.Updated(box) ->
          Edited(Editor(..editor, mode: Importing(box, rebuild)))
      }
    Picking(box, rebuild) ->
      case combobox.update(box, key) {
        combobox.Cancelled -> Edited(Editor(..editor, mode: Navigating))
        combobox.Selected(value) ->
          Edited(Editor(..editor, mode: Navigating, buffer: rebuild(value)))
        combobox.Updated(box) ->
          Edited(Editor(..editor, mode: Picking(box, rebuild)))
      }
  }
}

fn text_key(
  editor: Editor,
  editing: input.InputState,
  key: String,
  mode: fn(input.InputState) -> Mode,
  submit: fn(String) -> Result(Buffer, String),
) -> Outcome {
  case key {
    "esc" -> Edited(Editor(..editor, mode: Navigating))
    "enter" ->
      case submit(editing.value) {
        Ok(buffer) -> Edited(Editor(..editor, mode: Navigating, buffer:))
        Error(message) -> Edited(Editor(..editor, message: Some(message)))
      }
    _ -> Edited(Editor(..editor, mode: mode(combobox.edit_input(editing, key))))
  }
}

/// Paste EYG source over the selected expression, or text into a field.
pub fn paste(editor: Editor, text: String) -> Editor {
  case editor.mode {
    Navigating ->
      case buffer.set_expression(editor.buffer), shell.parse(text) {
        Ok(rebuild), Ok(expression) ->
          Editor(..editor, buffer: rebuild(expression))
        Error(Nil), _ -> fail(editor, "Select an expression to paste into")
        _, Error(reason) -> fail(editor, reason)
      }
    EnterText(editing, rebuild) ->
      Editor(
        ..editor,
        mode: EnterText(combobox.insert_text(editing, text), rebuild),
      )
    EnterInteger(editing, rebuild) ->
      Editor(
        ..editor,
        mode: EnterInteger(combobox.insert_text(editing, text), rebuild),
      )
    EnterCid(editing, rebuild) ->
      Editor(
        ..editor,
        mode: EnterCid(combobox.insert_text(editing, text), rebuild),
      )
    Picking(box, rebuild) ->
      Editor(..editor, mode: Picking(combobox.paste(box, text), rebuild))
    Importing(box, rebuild) ->
      Editor(..editor, mode: Importing(combobox.paste(box, text), rebuild))
  }
}

/// The key bindings, for the help panel.
pub const bindings = [
  #("enter", "run the program"),
  #("← → ↑ ↓", "move the selection"),
  #("a", "select the enclosing expression"),
  #("space", "jump to the next blank"),
  #("e / E", "assign to a variable, after / before"),
  #("n", "insert an integer"),
  #("s", "insert a string"),
  #("b", "insert a binary"),
  #("v", "insert a variable"),
  #("f", "insert a function"),
  #("c / C", "call the selection / call it once"),
  #("w", "call a function with the selection"),
  #("j", "insert a builtin"),
  #("p", "perform an effect"),
  #("h", "handle an effect"),
  #("r / R", "create a record / an empty record"),
  #("g", "select a field"),
  #("o", "overwrite a field"),
  #("l / L", "create a list / an empty list"),
  #("x", "spread a list"),
  #("t", "tag a value"),
  #("m", "match on a tag"),
  #("i", "edit the selected name or value"),
  #("< / >", "insert before / after"),
  #("q", "import a file from the file system"),
  #("#", "insert a content reference"),
  #("k", "collapse or expand"),
  #("d", "delete"),
  #("z / Z", "undo / redo"),
  #("ctrl+v", "paste EYG source"),
  #("esc", "cancel, or stop a running program"),
  #("?", "show or hide this help"),
]

fn command(editor: Editor, key: String) -> Outcome {
  case key {
    "enter" -> run(editor)
    "esc" -> Edited(editor)
    "right" -> navigate(editor, "move right", buffer.next)
    "left" -> navigate(editor, "move left", buffer.previous)
    "up" -> navigate(editor, "move up", buffer.up)
    "down" -> navigate(editor, "move down", buffer.down)
    "a" -> navigate(editor, "increase selection", buffer.increase)
    " " -> navigate(editor, "jump to blank", buffer.next_vacant)
    "k" -> navigate(editor, "toggle", buffer.toggle_open)
    "w" -> edit(editor, m.call_with())
    "E" -> edit(editor, m.assign_before())
    "e" -> edit(editor, m.assign())
    "R" -> edit(editor, m.create_empty_record())
    "r" -> edit(editor, m.create_record())
    "t" -> edit(editor, m.insert_tag())
    "i" -> edit(editor, m.insert())
    "o" -> edit(editor, m.overwrite())
    "p" -> edit(editor, m.perform(effect_types()))
    "s" -> edit(editor, m.insert_string())
    "d" -> edit(editor, m.delete())
    "f" -> edit(editor, m.insert_function())
    "g" -> edit(editor, m.select_field())
    "h" -> edit(editor, m.insert_handle(effect_types()))
    "j" -> edit(editor, m.insert_builtin())
    "L" -> edit(editor, m.create_empty_list())
    "l" -> edit(editor, m.create_list())
    "#" -> edit(editor, m.insert_reference())
    "Z" -> edit(editor, m.redo())
    "z" -> edit(editor, m.undo())
    "x" -> edit(editor, m.spread())
    "c" -> edit(editor, m.call_function())
    "C" -> edit(editor, m.call_once())
    "b" -> edit(editor, m.insert_binary())
    "n" -> edit(editor, m.insert_integer())
    "m" -> edit(editor, m.insert_case())
    "v" -> edit(editor, m.insert_variable())
    "<" -> edit(editor, m.insert_before())
    ">" -> edit(editor, m.insert_after())
    "q" -> import_file(editor)
    "@" -> Edited(fail(editor, "Packages are not available here"))
    _ -> Edited(fail(editor, "No action for " <> key <> ", press ? for help"))
  }
}

/// Choose a file to import in place of the selection.
fn import_file(editor: Editor) -> Outcome {
  case buffer.insert_explicit_reference(editor.buffer) {
    Error(_) -> Edited(fail(editor, "Select an expression to import into"))
    Ok(rebuild) -> {
      let items = list.map(editor.files, fn(path) { #(path, "file") })
      let box =
        combobox.Combobox(..combobox.new(items, ""), validate: fn(path) {
          case list.contains(editor.files, path) {
            True -> Ok(Nil)
            False -> Error("Choose a file")
          }
        })
      Edited(Editor(..editor, mode: Importing(box, rebuild)))
    }
  }
}

fn run(editor: Editor) -> Outcome {
  case expression(editor) {
    e.Vacant -> Edited(fail(editor, "Write a program first, press ? for help"))
    expression -> Run(expression)
  }
}

fn navigate(editor: Editor, name, move) -> Outcome {
  case move(editor.buffer) {
    Ok(buffer) -> Edited(Editor(..editor, buffer:))
    Error(_) -> Edited(fail(editor, "Can't " <> name))
  }
}

fn edit(editor: Editor, operation: m.Operation) -> Outcome {
  let m.Operation(name:, apply:) = operation
  let editor = case apply(editor.buffer) {
    Ok(m.Resolved(buffer)) -> Editor(..editor, buffer:)
    Ok(m.UserInput(m.EnterText(value, rebuild))) ->
      Editor(..editor, mode: EnterText(input.state_from_string(value), rebuild))
    Ok(m.UserInput(m.EnterInteger(value, rebuild))) -> {
      let value = case value {
        0 -> ""
        n -> int.to_string(n)
      }
      Editor(
        ..editor,
        mode: EnterInteger(input.state_from_string(value), rebuild),
      )
    }
    Ok(m.UserInput(m.PickSingle(picker.Typing(value, choices), rebuild))) -> {
      let box =
        combobox.Combobox(..combobox.new(choices, value), validate: fn(value) {
          case value {
            "" -> Error("Name cannot be empty")
            _ -> Ok(Nil)
          }
        })
      Editor(..editor, mode: Picking(box, rebuild))
    }
    Ok(m.UserInput(m.PickCid(_, rebuild))) ->
      Editor(..editor, mode: EnterCid(input.state_new(), rebuild))
    Ok(m.UserInput(_)) -> fail(editor, "Can't " <> name <> " here")
    Error(Nil) -> fail(editor, "Can't " <> name <> " here")
  }
  Edited(editor)
}

fn fail(editor: Editor, message: String) -> Editor {
  Editor(..editor, message: Some(message))
}
