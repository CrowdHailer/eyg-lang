import gleam/dynamic
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}
import lustre/event
import morph/lustre/render
import drafting/state

pub fn render(app) {
  let state.State(zip, mode) = app
  // containter for relative positioning
  h.div([a.class("relative")], [
    h.div([], case mode {
      state.Navigate -> []
      state.Pallet(search, actions, index) ->
        overlay([pallet(search, actions, index)])
      state.RequireString(value, rebuild) -> overlay([string_input(value)])
    }),
    h.div(
      [
        a.class("flex flex-col justify-center min-h-screen p-4"),
        a.style([#("align-items", "center")]),
      ],
      [h.div([a.class("w-full max-w-4xl font-mono")], [surface(zip)])],
    ),
  ])
}

pub fn surface(zip) {
  h.div(
    [
      a.class("outline-none"),
      a.attribute("tabindex", "0"),
      event.on_keydown(state.KeyDown),
      a.id("code"),
    ],
    [render.projection(zip)],
  )
}

pub fn pallet(search, actions, index) {
  let assert Ok(#(_, current, _)) = list.at(actions, index)

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
      let #(name, apply, shortkey) = action
      h.div(
        [
          a.class("px-4 py-2 flex"),
          a.classes([#("bg-gray-800", i == index)]),
          event.on_click(state.Do(apply)),
        ],
        [
          h.span([], [text(name)]),
          h.span([a.class("flex-grow")], []),
          h.span([], case shortkey {
            Some(k) -> [
              h.span(
                [
                  a.class(
                    "border rounded w-5 leading-snug inline-block font-mono text-center",
                  ),
                ],
                [text(k)],
              ),
            ]
            None -> []
          }),
        ],
      )
    })
  ])
}

pub fn string_input(value) {
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
  ])
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
    h.div(
      [
        a.class(
          "absolute top-0 bottom-0 right-0 left-0 flex flex-col justify-center",
        ),
        a.style([#("align-items", "center"), #("backdrop-filter", "blur(3px)")]),
      ],
      [
        h.div(
          [a.class("bg-black text-white border-black max-w-2xl border w-full")],
          content,
        ),
      ],
    ),
  ]
}
