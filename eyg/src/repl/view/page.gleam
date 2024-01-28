import gleam/float
import gleam/io
import gleam/int
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import glance
import lustre/attribute.{class, id}
import lustre/element.{text}
import lustre/element/html.{
  button, div, form, hr, iframe, input, p, pre, span, textarea,
}
import lustre/effect
import lustre/event.{on_click}
import repl/reader
import repl/runner
import repl/state.{State, Wrap}
import scintilla/value as v

pub fn render(state) {
  let State(scope, statement, reason, history) = state
  div([class("vstack")], [
    div([class("hstack rounded-lg max-w-2xl glass")], [
      div([class("cover")], [span([class("font-bold")], [text("Gleam REPL")])]),
      div(
        [class("expand bg-gray-700 rounded-lg m-4 text-gray-300")],
        list.append(render_history(history), [
          form(
            [class("hstack wrap"), event.on_submit(Wrap(execute_statement))],
            [
              span([class("mr-2")], [text(">")]),
              textarea([
                event.on_input(fn(value) {
                  Wrap(fn(state) {
                    #(State(..state, statement: value), effect.none())
                  })
                }),
                attribute.value(dynamic.from(statement)),
                attribute.attribute("rows", {
                  let lines =
                    string.split(statement, "\n")
                    |> list.length
                  // already one extra section than number or newlines. there was an issue with \r
                  int.to_string(lines)
                }),
                // attribute.autofocus(True),
                attribute.attribute("autofocus", "true"),
                class(
                  "w-full bg-transparent border-b border-gray-500 focus:border-gray-200 outline-none",
                ),
              ]),
              div([], [
                button([class("p-1 bg-orange-3 text-white rounded")], [
                  text("run"),
                ]),
              ]),
            ],
          ),
          ..case reason {
            Some(bad) -> [
              div(
                [
                  class(
                    "border-b border-red-600 ml-4 mt-4 p-1 rounded-md text-gray-300 text-red-400 text-white",
                  ),
                ],
                [text(string.inspect(bad))],
              ),
            ]
            None -> []
          }
        ]),
      ),
    ]),
  ])
}

fn render_history(history) {
  list.flat_map(list.reverse(history), fn(h) {
    let #(code, answer) = h
    [
      div([class("hstack wrap")], [
        // span([class("mr-2")], [text(">")]),
        pre([class("expand")], [text("> "), text(code)]),
      ]),
      div([], [text(answer)]),
    ]
  })
}

fn execute_statement(state) {
  let State(state, src, _reason, history) = state
  let assert Ok(#(term, _)) = reader.parse(src)
  case runner.read(term, state) {
    Ok(#(value, state)) -> {
      let output = case value {
        Some(value) -> render_value(value)
        None -> ""
      }

      #(State(state, "", None, [#(src, output), ..history]), effect.none())
    }
    // TODO should be handled in runner
    // Error(runner.Finished(scope)) -> {
    //   let state = State(scope, "", None, [#(src, ""), ..history])
    //   #(state, effect.none())
    // }
    Error(reason) -> {
      let state = State(state, src, Some(reason), history)
      #(state, effect.none())
    }
  }
}

pub fn render_value(value) {
  case value {
    v.I(x) -> int.to_string(x)
    v.F(x) -> float.to_string(x)
    v.S(x) -> string.inspect(x)
    v.T(elements) -> "recursive print needed"
    v.R(constructor, []) -> constructor
    v.R(constructor, fields) -> {
      let parts =
        list.map(fields, fn(f) {
          let glance.Field(label, value) = f
          case label {
            Some(label) -> string.concat([label, ": ", render_value(value)])
            None -> render_value(value)
          }
        })
        |> list.intersperse(", ")
      list.flatten([[constructor, "("], parts, [")"]])
      |> string.concat
    }
    v.Constructor(label, _) -> label
    v.Closure(_, _, _) -> "closure"
    item -> string.inspect(item)
  }
}
