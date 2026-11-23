//// A structural editor for the programs a shell runs.
////
//// Keys edit and navigate code with the bindings of the EYG shell, see `morph/terminal`,
//// and `q` imports a file from the box. EYG text that is pasted replaces the expression in focus.
//// When an edit needs a value it is entered in a box over the middle of the screen.
//// Text and numbers are typed with a cursor that moves, a variable, builtin, package or file is chosen
//// from suggestions that show each with its type.
//// The code is type checked after each edit, the types of packages are looked up through the hub,
//// which blocks the interface while a package that is not cached is fetched.

import cloud/beam/execute
import etui/backend
import etui/buffer as screen_buffer
import etui/geometry
import etui/span
import etui/style
import etui/widgets/block
import etui/widgets/clear
import etui/widgets/input
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/cache
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import morph/buffer.{type Buffer}
import morph/editable as e
import morph/lustre/render
import morph/manipulation as m
import morph/picker
import morph/projection
import morph/terminal
import morph/terminal/combobox
import morph/terminal/field
import multiformats/cid/v1
import touch_grass/harness/computer
import touch_grass/interface
import touch_grass/policy

pub type Editor {
  Editor(buffer: Buffer, input: Option(Input))
}

/// A value being typed for an edit.
pub type Input {
  /// Typed, such as text or a number.
  Typed(
    label: String,
    widget: input.InputWidget,
    editing: input.InputState,
    submit: fn(String) -> Result(Buffer, String),
  )
  /// Chosen from suggestions, each with its type.
  Picking(
    label: String,
    box: combobox.Combobox,
    submit: fn(String) -> Result(Buffer, String),
  )
}

pub fn new() -> Editor {
  Editor(buffer.empty(), None)
}

/// The program, an editor with nothing written has none.
pub fn program(editor: Editor) -> Result(ir.Node(Nil), Nil) {
  case projection.rebuild(editor.buffer.projection) {
    e.Vacant -> Error(Nil)
    expression ->
      Ok(e.to_annotated(expression, []) |> ir.map_annotation(fn(_) { Nil }))
  }
}

// The effects code in a shell can perform.
fn effects() {
  computer.effects()
  |> policy.match_rules(execute.rules)
  |> list.map(fn(rule) { rule.0 })
  |> interface.types
}

/// Handle a key, the error is a message for the person typing.
/// `files` are the files of the box, offered when importing.
/// The state is returned with the modules that were looked up to check the code.
pub fn key(
  editor: Editor,
  key: String,
  state: execute.State,
  files: List(String),
) -> #(Result(Editor, String), execute.State) {
  let edited = case editor.input, key {
    Some(input), _ -> typing(editor, input, key)
    None, "q" -> import_(editor, files)
    None, _ -> navigating(editor, key, state)
  }
  checked(edited, state)
}

/// Replace the expression in focus with the program in the text.
pub fn paste(
  editor: Editor,
  text: String,
  state: execute.State,
) -> #(Result(Editor, String), execute.State) {
  case editor.input {
    Some(Picking(..) as input) -> #(
      picking(editor, input, backend.Paste(text)),
      state,
    )
    Some(Typed(widget:, editing:, ..) as input) -> {
      let editing =
        string.replace(text, "\n", " ")
        |> string.to_graphemes
        |> list.fold(editing, fn(editing, char) {
          input.insert_char(widget, editing, char)
        })
      #(Ok(Editor(..editor, input: Some(Typed(..input, editing:)))), state)
    }
    _ -> replace(editor, text, state)
  }
}

fn replace(editor: Editor, text, state) {
  let pasted = case
    buffer.set_expression(editor.buffer),
    parser.all_from_string(text)
  {
    Ok(rebuild), Ok(source) ->
      Ok(
        Editor(
          ..editor,
          buffer: rebuild(e.from_annotated(source) |> e.open_all),
        ),
      )
    Error(Nil), _ -> Error("Select an expression to paste into")
    _, Error(reason) -> Error(parser.format_error(reason, text))
  }
  checked(pasted, state)
}

fn import_(editor: Editor, files) {
  case buffer.insert_explicit_reference(editor.buffer) {
    Error(Nil) -> Error("Select an expression to import into")
    Ok(rebuild) -> {
      let files = list.map(files, fn(path) { #(path, "file") })
      let input =
        Picking("Import a file", combobox.new(files), fn(path) {
          case string.trim(path) {
            "" -> Error("Choose a file to import")
            path -> Ok(rebuild(ir.Relative(path)))
          }
        })
      Ok(Editor(..editor, input: Some(input)))
    }
  }
}

fn checked(edited, state) {
  case edited {
    Ok(Editor(buffer:, ..) as editor) if buffer.analysis == None -> {
      let #(buffer, state) = check(editor.buffer, state)
      #(Ok(Editor(..editor, buffer:)), state)
    }
    _ -> #(edited, state)
  }
}

fn check(buffer, state) {
  let context = infer.pure() |> infer.with_effects(effects())
  do_check(buffer.check(buffer, context), state)
}

fn do_check(step, state) {
  case step {
    infer.Done(buffer) -> #(buffer, state)
    infer.Lookup(reference, resume) -> {
      let #(type_, state) = execute.lookup_type(reference, state)
      do_check(resume(result.replace_error(type_, Nil)), state)
    }
  }
}

fn typing(editor: Editor, input: Input, key) {
  case input {
    Picking(..) -> picking(editor, input, backend.KeyPress(key))
    Typed(widget:, editing:, submit:, ..) ->
      case key {
        "esc" -> Ok(Editor(..editor, input: None))
        "enter" -> submitted(submit, editing.value)
        _ -> {
          let editing = field.edit(widget, editing, key)
          Ok(Editor(..editor, input: Some(Typed(..input, editing:))))
        }
      }
  }
}

fn submitted(submit: fn(String) -> Result(Buffer, String), value) {
  case submit(value) {
    Ok(buffer) -> Ok(Editor(buffer:, input: None))
    Error(reason) -> Error(reason)
  }
}

fn picking(editor, input, event) {
  let assert Picking(submit:, ..) = input
  case combobox.update(event, input.box) {
    combobox.Cancelled -> Ok(Editor(..editor, input: None))
    combobox.Selected(value) -> submitted(submit, value)
    combobox.Updated(box) ->
      Ok(Editor(..editor, input: Some(Picking(..input, box:))))
  }
}

fn navigating(editor: Editor, key, state: execute.State) {
  let packages =
    dict.to_list(state.cache.packages)
    |> list.map(fn(entry) { #(entry.0, { entry.1 }.version) })
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  case terminal.binding(key, effects(), packages) {
    Ok(terminal.Move(name, move)) ->
      case move(editor.buffer) {
        Ok(buffer) -> Ok(Editor(..editor, buffer:))
        Error(Nil) -> Error("Can't " <> name)
      }
    Ok(terminal.Edit(m.Operation(name:, apply:))) ->
      case apply(editor.buffer) {
        Ok(m.Resolved(buffer)) -> Ok(Editor(..editor, buffer:))
        Ok(m.UserInput(asked)) ->
          Ok(Editor(..editor, input: Some(ask(asked, state))))
        Error(Nil) -> Error("Can't " <> name <> " here")
      }
    Error(Nil) -> Error("Nothing is bound to " <> key)
  }
}

fn ask(asked, state: execute.State) -> Input {
  // The choices offered and their types, with what has been typed so far.
  let choosing = fn(picker: picker.Picker) {
    case picker {
      picker.Typing(value, choices) ->
        combobox.Combobox(
          ..combobox.new(choices),
          input: input.state_from_string(value),
        )
      picker.Scrolling(..) -> combobox.new([])
    }
  }
  case asked {
    m.EnterText(value, rebuild) ->
      Typed(
        "Text",
        input.input_new("Enter text"),
        input.state_from_string(value),
        fn(value) { Ok(rebuild(value)) },
      )
    m.EnterInteger(value, rebuild) ->
      Typed(
        "Number",
        input.input_new("Enter a whole number")
          |> input.with_validator(fn(value) {
            int.parse(value)
            |> result.replace(Nil)
            |> result.replace_error("Enter a whole number")
          }),
        input.state_from_string(int.to_string(value)),
        fn(value) {
          case int.parse(value) {
            Ok(value) -> Ok(rebuild(value))
            Error(Nil) -> Error("Enter a whole number")
          }
        },
      )
    m.PickSingle(picker, rebuild) ->
      Picking("Choose a value", choosing(picker), fn(value) {
        case value {
          "" -> Error("Enter a name")
          _ -> Ok(rebuild(value))
        }
      })
    m.PickRelease(picker, rebuild) ->
      Picking("Choose a package", choosing(picker), fn(name) {
        case cache.package(state.cache, name) {
          Ok(cache.Entry(version:, module:, ..)) ->
            Ok(rebuild(ir.Release(name, version, module)))
          Error(Nil) -> Error("Choose a published package")
        }
      })
    m.PickCid(_, rebuild) -> {
      let parse = fn(value) {
        let value = case value {
          "#" <> value -> value
          value -> value
        }
        v1.from_string(value)
        |> result.map(fn(parsed) { parsed.0 })
        |> result.replace_error("Enter a content reference")
      }
      Typed(
        "Content reference",
        input.input_new("Enter a content reference")
          |> input.with_validator(fn(value) {
            parse(value) |> result.replace(Nil)
          }),
        input.state_new(),
        fn(value) { parse(value) |> result.map(rebuild) },
      )
    }
  }
}

/// The code with the focus marked.
pub fn lines(editor: Editor, active: Bool) -> List(span.Line) {
  let errors = buffer.block_errors(editor.buffer)
  let code = case projection.rebuild(editor.buffer.projection) {
    e.Vacant -> [
      span.line_new([
        span.span_styled(
          "Write EYG…",
          terminal.focus_style(style.default_style(), True, active),
        ),
      ]),
    ]
    _ ->
      render.projection(editor.buffer.projection, render.Statements, errors)
      |> terminal.lines(active && editor.input == None)
  }
  code
}

/// Draw the value being entered in the middle of the area, over what is there.
pub fn render_input(
  editor: Editor,
  screen: screen_buffer.Buffer,
  area: geometry.Rect,
) -> screen_buffer.Buffer {
  case editor.input {
    Some(Typed(label:, widget:, editing:, ..)) ->
      field.dialog(screen, area, label, widget, editing)
    Some(Picking(label:, box:, ..)) -> {
      let dialog = field.centered(area, 12)
      let border =
        block.block_new()
        |> block.with_border(block.Rounded)
        |> block.with_style(style.Rgb(97, 175, 239), style.Default)
        |> block.with_bg_fill
        |> block.with_title(label, block.Top)
        |> block.with_padding(0, 0, 1, 1)
      screen
      |> clear.render(dialog)
      |> block.render(dialog, border)
      |> combobox.render(block.inner(dialog, border), box)
    }
    _ -> screen
  }
}

/// Code as it is shown once it has been sent, without a focus.
pub fn sent(editor: Editor) -> List(span.Line) {
  code(projection.rebuild(editor.buffer.projection))
}

/// A program that was sent, as it was shown.
pub fn program_lines(program: ir.Node(Nil)) -> List(span.Line) {
  code(e.from_annotated(program))
}

fn code(expression) {
  render.statements(expression, [])
  |> list.flat_map(terminal.lines(_, False))
}
