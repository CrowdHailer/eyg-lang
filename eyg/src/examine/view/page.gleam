import examine/state.{
  Compilation, Highlight, Inference, Input, Interpret, Switch,
}
import eyg/analysis/type_/binding/debug
import eyg/interpreter/value as v
import eyg/runtime/break as old_break
import eyg/runtime/value as old_value
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute.{class, classes, id}
import lustre/element.{text}
import lustre/element/html.{div, p, pre, span, textarea}
import lustre/event.{on_click, on_input}
import website/components/tree

pub fn render(s: state.State) {
  div([class("vstack wrap")], [
    div([class("hstack wrap")], [
      div([class("expand")], []),
      div([on_click(Switch(Inference))], [
        span([class("m-2 inline-block font-bold")], [text("infer")]),
      ]),
      div([on_click(Switch(Interpret))], [
        span([class("m-2 inline-block font-bold")], [text("interpret")]),
      ]),
      div([on_click(Switch(Compilation))], [
        span([class("m-2 inline-block font-bold")], [text("compile")]),
      ]),
    ]),
    case s.view {
      Inference -> render_inference(s)
      Interpret -> render_interpretation(s)
      Compilation -> render_compilation(s)
    },
  ])
}

fn render_inference(s) {
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
  //  expand hstack and toggle to compile

  div([class("hstack expand")], [
    // container https://codersblock.com/blog/highlight-text-inside-a-textarea/
    div([class("expand cover bg-blue-100")], [
      div([class("relative h-full bg-white rounded")], [
        div(
          [class("absolute left-0 right-0 p-2")],
          list.map(highlights, fn(c) {
            let cl =
              option.unwrap(c, "")
              |> string.append(" h-6")
            div([class(cl)], [span([], [text(" ")])])
          }),
        ),
        textarea(
          [
            id("source"),
            class(
              "absolute left-0 right-0 p-2 h-full bg-transparent text-mono m-0",
            ),
            // event.on("select", fn(e) {
            //   let e = dynamicx.unsafe_coerce(e)
            //   io.debug(evt.target(e))
            //   todo as "select"
            // }),
            // Ok(Select(e))
            on_input(Input),
          ],
          state.source(s),
        ),
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
                span([], [text(debug.mono(type_))]),
              ])
            Error(reason) ->
              div([class("bg-red-300")], [
                span([], [text(debug.reason(reason))]),
              ])
          }
        }),
      ),
    ]),
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
            span([], [text(debug.effect(effect))]),
          ])
        }),
      ),
    ]),
  ])
  //   Error(reason) -> p([], [text(string.inspect(reason))])
  // }
}

fn render_interpretation(s) {
  let result = state.interpret(s)
  div([class("hstack expand")], [
    // container https://codersblock.com/blog/highlight-text-inside-a-textarea/
    div([class("expand cover bg-blue-100")], [
      div([class("relative h-full bg-white rounded")], [
        div([class("absolute left-0 right-0 p-2")], []),
        textarea(
          [
            id("source"),
            class(
              "absolute left-0 right-0 p-2 h-full bg-transparent text-mono m-0",
            ),
            on_input(Input),
          ],
          state.source(s),
        ),
      ]),
    ]),
    div([class("cover expand")], [
      div([class("vstack wrap")], case result {
        Ok(#(assignments, page)) -> {
          [
            div(
              [class("cover")],
              list.map(assignments, fn(a) {
                let #(_line, assignments) = a
                let t =
                  list.filter_map(list.reverse(assignments), fn(a) {
                    case a {
                      Ok(#(k, value)) ->
                        case k, value {
                          "$", _ -> Error(Nil)
                          _, v.Closure(_, _, _) -> Error(Nil)
                          _, _ ->
                            Ok(
                              string.concat([k, " = ", old_value.debug(value)]),
                            )
                        }
                      Error(reason) -> Ok(old_break.reason_to_string(reason))
                    }
                  })
                  |> list.intersperse(", ")
                  |> string.concat()
                p([class("h-6")], [text(t)])
              }),
            ),
            div(
              [
                id("sandbox"),
                attribute.attribute("dangerous-unescaped-html", page),
                class("bg-green-2 expand cover"),
              ],
              [],
            ),
          ]
        }
        Error(reason) -> [text(string.inspect(reason))]
      }),
    ]),
  ])
}

fn render_compilation(s) {
  let result = state.compile(s)
  div([class("hstack expand")], [
    // container https://codersblock.com/blog/highlight-text-inside-a-textarea/
    div([class("expand cover bg-blue-100")], [
      div([class("relative h-full bg-white rounded")], [
        div([class("absolute left-0 right-0 p-2")], []),
        textarea(
          [
            id("source"),
            class(
              "absolute left-0 right-0 p-2 h-full bg-transparent text-mono m-0",
            ),
            on_input(Input),
          ],
          state.source(s),
        ),
      ]),
    ]),
    div([class("cover expand")], [
      p([], [text("Compiled")]),
      p([], case result {
        Ok(compiled) -> [pre([class("leading-none")], [text(compiled)])]
        Error(reason) -> [text(string.inspect(reason))]
      }),
    ]),
  ])
}
