import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}
import lustre/event
import drafting/session as d
import drafting/view/page
import morph/lustre/render
import eyg/runtime/value as v
import spotless/state

pub fn render(app) {
  let state.State(previous, current, error) = app
  // containter for relative positioning
  h.div([a.class("")], [
    h.div(
      [],
      list.map(list.reverse(previous), fn(p) {
        let #(value, prog) = p
        h.div([a.class("mt-6 p-1 border-2 rounded border-blue-700 font-mono")], [
          h.div([], render.top(prog)),
          h.div([a.class("bg-gray-200")], [text(v.debug(value))]),
        ])
      }),
    ),
    h.div([a.class("mt-6 p-1 border-2 rounded border-blue-700")], [
      h.div([a.class("font-mono")], [
        page.surface(current.projection)
        |> element.map(state.Drafting),
      ]),
    ]),
    h.div([], case current.mode {
      d.Navigate ->
        case error {
          Some(reason) -> [
            h.div(
              [
                a.class(
                  "bg-red-700 text-white border-black mx-auto max-w-2xl border w-full rounded",
                ),
              ],
              [text(reason)],
            ),
          ]
          None -> []
        }
      d.SelectAction(search, actions, index) ->
        overlay([
          page.pallet(search, todo, index)
          |> element.map(state.Drafting),
        ])
      d.EditString(value, _rebuild) ->
        overlay([
          page.string_input(value)
          |> element.map(state.Drafting),
        ])
    }),
    h.div(
      [
        a.class("mx-auto max-w-2xl w-full text-right"),
        event.on_click(state.LoadSource),
      ],
      [h.button([], [text("load source")])],
    ),
  ])
}

fn overlay(content) {
  [
    h.div(
      [
        a.class(
          "bg-black text-white border-black mx-auto max-w-2xl border w-full rounded",
        ),
      ],
      content,
    ),
  ]
}
