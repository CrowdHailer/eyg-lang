import gleam/io
import gleam/dynamic
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute.{class, classes, id, value}
import lustre/element.{text}
import lustre/element/html.{div, p, pre, span, textarea}
import lustre/event.{on_click, on_input}
import plinth/browser/event as evt
import eygir/tree
import eyg/analysis/type_/binding/debug
import textual/state.{Highlight, Input}

pub fn render(s) {
  let #(err, highlights, source, spans, acc) = case state.information(s) {
    Ok(#(highlights, source, spans, acc)) -> #(
      Ok(Nil),
      highlights,
      tree.lines(source),
      spans,
      acc,
    )
    Error(reason) -> #(Error(reason), [], [], [], [])
  }
  let focused = case s.cursor {
    // TODO make full range selection
    Some(cursor) ->
      list.index_fold(spans, -1, fn(recent, span, i) {
        let #(start, end) = span
        case start <= cursor && cursor <= end {
          True -> i
          False -> recent
        }
      })
    None -> -1
  }
  div([class("hstack")], [
    // container https://codersblock.com/blog/highlight-text-inside-a-textarea/
    div([class("expand cover bg-blue-100")], [
      div([class("relative h-full bg-white rounded")], [
        div(
          [class("absolute left-0 right-0 p-2")],
          // [
          //   div([class("h-6")], [span([], [text(" ")])]),
          //   div([class("h-6 bg-red-200")], [span([], [text(" ")])]),
          //   div([class("h-6")], [span([], [text(" ")])]),
          // ]
          list.map(highlights, fn(c) {
            let cl =
              option.unwrap(c, "")
              |> string.append(" h-6")
            div([class(cl)], [span([], [text(" ")])])
          }),
        ),
        textarea([
          id("source"),
          class(
            "absolute left-0 right-0 p-2 h-full bg-transparent text-mono m-0",
          ),
          // event.on("select", fn(e) {
          //   let e = dynamic.unsafe_coerce(e)
          //   io.debug(evt.target(e))
          //   todo as "select"
          // }),
          // Ok(Select(e))
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
      p([], [text("spans")]),
      div(
        [class("leading-none")],
        list.map(spans, fn(span) {
          let #(start, end) = span
          div([], [
            pre([on_click(Highlight(span))], [
              text(int.to_string(start)),
              text(" - "),
              text(int.to_string(end)),
            ]),
          ])
        }),
      ),
    ]),
    div([class("cover")], [
      p([], [text("Inferred type")]),
      div(
        [class("leading-none")],
        list.index_map(acc, fn(x, i) {
          let #(fail, type_, effect) = x
          case fail {
            Ok(Nil) ->
              div([classes([#("bg-green-200", i == focused)])], [
                span([], [text(debug.render_type(type_))]),
              ])
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
    // TODO live eval
    // TODO range to line
    // Need position in file to tree 
    // cli args for type checking
    // cli for dump tree to file
    // meta data in the tree means no need to build path in the interpreter
    // could keep a tree of location information when parsing BUT if linear that just a case of building linear
    // metadata could be linear position 
    div([class("expand cover")], [
      p([], [text("Effects")]),
      div(
        [class("leading-none")],
        list.index_map(acc, fn(x, i) {
          let #(fail, type_, effect) = x
          div([classes([#("bg-green-200", i == focused)])], [
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
