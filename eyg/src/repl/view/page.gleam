import gleam/float
import gleam/io
import gleam/int
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import glexer
import glance
import lustre/attribute.{class, id}
import lustre/element.{text}
import lustre/element/html.{button, div, form, hr, iframe, input, p, span}
import lustre/effect
import lustre/event.{on_click}
import repl/reader
import repl/runner
import repl/state.{State, Wrap}

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
              input([
                event.on_input(fn(value) {
                  Wrap(fn(state) {
                    #(State(..state, statement: value), effect.none())
                  })
                }),
                attribute.value(dynamic.from(statement)),
                // attribute.autofocus(True),
                attribute.attribute("autofocus", "true"),
                class(
                  "w-full bg-transparent border-b border-gray-500 focus:border-gray-200 outline-none",
                ),
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
        span([class("mr-2")], [text(">")]),
        span([class("expand")], [text(code)]),
      ]),
      div([], [text(answer)]),
    ]
  })
}

fn execute_statement(state) {
  let State(scope, src, _reason, history) = state
  let assert Ok(reader.Statements(statements)) = reader.parse(src)
  case runner.exec(statements, scope) {
    Ok(value) -> {
      let output = case value {
        runner.I(x) -> int.to_string(x)
        runner.F(x) -> float.to_string(x)
        runner.S(x) -> string.inspect(x)
        runner.T(elements) -> "recursive print needed"
        runner.R("True", []) -> "True"
        runner.R("False", []) -> "False"
        runner.Closure(_, _, _) -> "closure"
      }
      #(State(scope, "", None, [#(src, output), ..history]), effect.none())
    }
    Error(runner.Finished(scope)) -> {
      let state = State(scope, "", None, [#(src, ""), ..history])
      #(state, effect.none())
    }
    Error(reason) -> {
      let state = State(scope, src, Some(reason), history)
      #(state, effect.none())
    }
  }
}
