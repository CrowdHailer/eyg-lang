//// A structural editor for the programs a shell runs.
////
//// Keys edit and navigate code with the bindings of the EYG shell, see `morph/terminal`,
//// and `q` imports a file from the box. EYG text that is pasted replaces the expression in focus.
//// When an edit needs a value, such as a name or a number, it is typed on a line below the code.
//// The code is type checked after each edit, the types of packages are looked up through the hub,
//// which blocks the interface while a package that is not cached is fetched.

import cloud/beam/execute
import etui/span
import etui/style
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
import multiformats/cid/v1
import touch_grass/harness/computer
import touch_grass/interface
import touch_grass/policy

pub type Editor {
  Editor(buffer: Buffer, input: Option(Input))
}

/// A value being typed for an edit, `suggestions` are offered as it is typed.
pub type Input {
  Input(
    label: String,
    value: String,
    suggestions: List(String),
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
      let input =
        Input("Import", "", files, fn(path) {
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
  case key {
    "esc" -> Ok(Editor(..editor, input: None))
    "enter" ->
      case input.submit(input.value) {
        Ok(buffer) -> Ok(Editor(buffer:, input: None))
        Error(reason) -> Error(reason)
      }
    "backspace" -> edit(editor, input, string.drop_end(input.value, 1))
    "tab" ->
      case matching(input) {
        [first, ..] -> edit(editor, input, first)
        [] -> Ok(editor)
      }
    _ ->
      case string.length(key) {
        1 -> edit(editor, input, input.value <> key)
        _ -> Ok(editor)
      }
  }
}

fn edit(editor, input, value) {
  Ok(Editor(..editor, input: Some(Input(..input, value:))))
}

/// The suggestions that contain what has been typed.
pub fn matching(input: Input) -> List(String) {
  list.filter(input.suggestions, string.contains(_, input.value))
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
  let suggested = fn(picker: picker.Picker) {
    case picker {
      picker.Typing(value, suggestions) -> #(
        value,
        list.map(suggestions, fn(s) { s.0 }),
      )
      picker.Scrolling(..) -> #("", [])
    }
  }
  case asked {
    m.EnterText(value, rebuild) ->
      Input("Text", value, [], fn(value) { Ok(rebuild(value)) })
    m.EnterInteger(value, rebuild) ->
      Input("Number", int.to_string(value), [], fn(value) {
        case int.parse(value) {
          Ok(value) -> Ok(rebuild(value))
          Error(Nil) -> Error("Enter a whole number")
        }
      })
    m.PickSingle(picker, rebuild) -> {
      let #(value, suggestions) = suggested(picker)
      Input("Name", value, suggestions, fn(value) {
        case value {
          "" -> Error("Enter a name")
          _ -> Ok(rebuild(value))
        }
      })
    }
    m.PickRelease(picker, rebuild) -> {
      let #(value, suggestions) = suggested(picker)
      Input("Package", value, suggestions, fn(name) {
        case cache.package(state.cache, name) {
          Ok(cache.Entry(version:, module:, ..)) ->
            Ok(rebuild(ir.Release(name, version, module)))
          Error(Nil) -> Error("Choose a published package")
        }
      })
    }
    m.PickCid(_, rebuild) ->
      Input("Content reference", "", [], fn(value) {
        let value = case value {
          "#" <> value -> value
          value -> value
        }
        case v1.from_string(value) {
          Ok(#(cid, _)) -> Ok(rebuild(cid))
          Error(_) -> Error("Enter a content reference")
        }
      })
  }
}

/// The code with the focus marked, and the value being typed if there is one.
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
  case editor.input {
    None -> code
    Some(input) ->
      list.append(code, [
        span.line_new([
          span.span_styled(input.label <> " ", style.dim_style()),
          span.span_plain(input.value),
          span.span_styled("▏", style.reversed()),
          span.span_styled(
            "  " <> string.join(list.take(matching(input), 5), "  "),
            style.dim_style(),
          ),
        ]),
      ])
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
