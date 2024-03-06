import gleam/dynamic
import gleam/list
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}
import lustre/event
import notepad/view/page
import notepad/view/code
import spotless/state

pub fn render(app) {
  let state.State(previous, zip, mode) = app
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
          code.top(prog),
        )
      }),
    ),
    // |> code.to_fat_lines()
    h.div(
      [
        a.class("max-w-2xl mx-auto mt-6 p-1 border-2 rounded border-blue-700"),
        a.id("code"),
        a.attribute("tabindex", "0"),
        event.on_keydown(state.KeyDown),
      ],
      [h.div([a.class("w-full max-w-4xl font-mono")], [page.print(zip)])],
    ),
    h.div([], case mode {
      state.Navigate -> []
      state.Pallet(search, actions, index) ->
        overlay(pallet(search, actions, index))
      state.RequireString(value, rebuild) -> overlay(string_input(value))
    }),
  ])
}

fn pallet(search, actions, index) {
  let assert Ok(#(_, current)) = list.at(actions, index)
  [
    h.form([event.on_submit(state.Do(current))], [
      h.div([a.class("w-full p-2")], []),
      h.input([
        a.class(
          "block w-full bg-transparent border-l-8 border-green-700 focus:border-green-300 px-2 py-2 outline-none",
        ),
        a.id("focus-input"),
        a.value(dynamic.from(search)),
        // a.autofocus(True),
        a.attribute("autocomplete", "off"),
        a.attribute("autofocus", "true"),
        event.on_keydown(state.KeyDown),
        event.on_input(state.UpdateInput),
      ]),
      h.hr([a.class("mx-40 my-3 border-green-700")]),
      ..list.index_map(actions, fn(action, i) {
        let #(name, apply) = action
        h.div(
          [
            a.class("px-4 py-2"),
            a.classes([#("bg-gray-800", i == index)]),
            event.on_click(state.Do(apply)),
          ],
          [text(name)],
        )
      })
    ]),
  ]
}

fn string_input(value) {
  [
    h.form([event.on_submit(state.DoIt)], [
      h.div([a.class("w-full p-2")], []),
      h.input([
        a.class(
          "block w-full bg-transparent border-l-8 border-green-700 focus:border-green-300 px-2 py-2 outline-none",
        ),
        a.id("focus-input"),
        a.value(dynamic.from(value)),
        // a.autofocus(True),
        a.attribute("autofocus", "true"),
        event.on_keydown(state.KeyDown),
        event.on_input(state.UpdateInput),
      ]),
      h.hr([a.class("mx-40 my-3 border-green-700")]),
    ]),
  ]
  // ..list.index_map(actions, fn(action, i) {
  //   let #(name, apply) = action
  //   h.div(
  //     [
  //       a.class("px-4 py-2"),
  //       a.classes([#("bg-gray-800", i == index)]),
  //       event.on_click(state.Do(apply)),
  //     ],
  //     [text(name)],
  //   )
  // })
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
