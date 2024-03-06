import gleam/dynamic
import gleam/list
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}
import lustre/event
import drafting/state as d
import drafting/view/page
import notepad/view/code
import eyg/runtime/value as v
import spotless/state

pub fn render(app) {
  let state.State(previous, current) = app
  // containter for relative positioning
  h.div([a.class("")], [
    h.div(
      [],
      list.map(previous, fn(p) {
        let #(value, prog) = p
        h.div(
          [
            a.class(
              "max-w-2xl mx-auto mt-6 p-1 border-2 rounded border-blue-700 font-mono",
            ),
          ],
          [
            h.div([], code.top(prog)),
            h.div([a.class("bg-gray-200")], [text(v.debug(value))]),
          ],
        )
      }),
    ),
    h.div(
      [a.class("max-w-2xl mx-auto mt-6 p-1 border-2 rounded border-blue-700")],
      [
        h.div([a.class("w-full max-w-4xl font-mono")], [
          page.surface(current.zip)
          |> element.map(state.Drafting),
        ]),
      ],
    ),
    h.div([], case current.mode {
      d.Navigate -> []
      d.Pallet(search, actions, index) ->
        overlay([
          page.pallet(search, actions, index)
          |> element.map(state.Drafting),
        ])
      d.RequireString(value, rebuild) ->
        overlay([
          page.string_input(value)
          |> element.map(state.Drafting),
        ])
    }),
    h.div([], []),
  ])
}

fn overlay(content) {
  [
    h.div([a.class("")], [
      h.div(
        [
          a.class(
            "bg-black text-white border-black mx-auto max-w-2xl border w-full rounded",
          ),
        ],
        content,
      ),
    ]),
  ]
}
