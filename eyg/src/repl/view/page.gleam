import gleam/float
import gleam/io
import gleam/int
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/string
import glexer
import glance
import lustre/attribute.{class, id}
import lustre/element.{text}
import lustre/element/html.{button, div, form, hr, iframe, input, p, span}
import lustre/effect
import lustre/event.{on_click}
import repl/runner
import repl/state.{State, Wrap}

pub fn render(state) {
  let State(statement, history) = state
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
  let State(src, history) = state
  let assert Ok(#(statement, rest)) =
    glexer.new(src)
    |> glexer.lex
    |> list.filter(fn(pair) { !glance.is_whitespace(pair.0) })
    |> glance.statement
  case runner.exec(statement, dict.new()) {
    Ok(value) -> {
      let output = case value {
        runner.I(x) -> int.to_string(x)
        runner.F(x) -> float.to_string(x)
        runner.B(x) -> string.inspect(x)
        runner.S(x) -> string.inspect(x)
        runner.T(elements) -> "recursive print needed"
        runner.Closure(_, _, _) -> "closure"
      }
      #(State("", [#(src, output), ..history]), effect.none())
    }
    Error(reason) -> {
      io.debug(reason)
      #(state, effect.none())
    }
  }
}
