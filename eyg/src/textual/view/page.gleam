import gleam/dynamic
import gleam/list
import gleam/string
import lustre/attribute.{class, value}
import lustre/element.{text}
import lustre/element/html.{div, p, pre, span, textarea}
import lustre/event.{on_input}
import eygir/tree
import eyg/analysis/fast_j/debug
import textual/state.{Input}

pub fn render(s) {
  let #(err, source, acc) = case state.information(s) {
    Ok(#(source, acc)) -> #(Ok(Nil), tree.lines(source), acc)
    Error(reason) -> #(Error(reason), [], [])
  }
  div([class("hstack")], [
    // container https://codersblock.com/blog/highlight-text-inside-a-textarea/
    div([class("expand cover bg-blue-100")], [
      div([class("relative h-full bg-white rounded")], [
        div([class("absolute left-0 right-0 p-2")], [
          div([class("h-6")], [span([], [text(" ")])]),
          div([class("h-6 bg-red-200")], [span([], [text(" ")])]),
          div([class("h-6")], [span([], [text(" ")])]),
        ]),
        textarea([
          class(
            "absolute left-0 right-0 p-2 h-full bg-transparent text-mono m-0",
          ),
          value(dynamic.from(state.source(s))),
          on_input(Input),
        ]),
      ]),
    ]),
    div([class("cover")], [
      p([], [text("Source Tree")]),
      div(
        [class("leading-none")],
        list.map(source, fn(x) { div([], [pre([], [text(x)])]) }),
      ),
      p([], case err {
        Ok(Nil) -> []
        Error(reason) -> [text(string.inspect(reason))]
      }),
    ]),
    div([class("cover")], [
      p([], [text("Inferred type")]),
      div(
        [class("leading-none")],
        list.map(acc, fn(x) {
          let #(fail, type_, effect) = x
          case fail {
            Ok(Nil) -> div([], [span([], [text(debug.render_type(type_))])])
            Error(reason) ->
              div([class("bg-red-300")], [
                span([], [text(debug.render_reason(reason))]),
              ])
          }
        }),
      ),
    ]),
    // span([], [text(" ")]),
    // span([], [text(debug.render_effects(effect))]),
    // TODO render errors
    // TODO live eval
    // TODO range to line
    div([class("expand cover")], [
      p([], [text("Effects")]),
      div(
        [class("leading-none")],
        list.map(acc, fn(x) {
          let #(fail, type_, effect) = x
          div([], [
            // span([], [text(debug.render_type(type_))]),
            // span([], [text(" ")]),
            span([], [text(debug.render_effects(effect))]),
          ])
        }),
      ),
    ]),
  ])
  //   Error(reason) -> p([], [text(string.inspect(reason))])
  // }
}
