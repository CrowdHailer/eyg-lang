import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}
import lustre/event
import morph/lustre/render
import drafting/session

pub fn render(app) {
  let session.Session(_, zip, mode) = app
  // containter for relative positioning
  h.div([a.class("relative")], [
    h.div([], case mode {
      session.Navigate -> []
      session.SelectAction(search, actions, index) ->
        overlay([pallet(search, actions, index)])
      session.EditString(value, _rebuild) -> overlay([string_input(value)])
      session.EditInteger(value, _rebuild) -> overlay([integer_input(value)])
      session.SelectBuiltin(value, suggestions, index, _) ->
        overlay([select_builtin(value, suggestions, index)])
      session.SelectVariable(_, _, _) -> todo
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
      event.on_keydown(session.KeyDown),
      a.id("code"),
    ],
    [render.projection(zip)],
  )
}

pub fn pallet(search, actions, index) {
  h.form([event.on_submit(session.DoIt)], [
    h.div([a.class("w-full p-2")], []),
    h.input([
      a.class(
        "block w-full bg-transparent border-l-8 border-green-700 focus:border-green-300 px-2 py-2 outline-none",
      ),
      a.id("focus-input"),
      a.value(search),
      // a.autofocus(True),
      a.attribute("autocomplete", "off"),
      a.attribute("autofocus", "true"),
      event.on_keydown(session.KeyDown),
      event.on_input(session.UpdateInput),
    ]),
    h.hr([a.class("mx-40 my-3 border-green-700")]),
    ..list.index_map(actions, fn(action, i) {
      let session.Binding(name, _apply, shortkey) = action
      h.div(
        [a.class("px-4 py-2 flex"), a.classes([#("bg-gray-800", i == index)])],
        // event.on_click(state.Do(apply)),
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

pub fn select_builtin(search, suggestions, index) {
  h.form([event.on_submit(session.DoIt)], [
    h.div([a.class("w-full p-2")], []),
    h.input([
      a.class(
        "block w-full bg-transparent border-l-8 border-green-700 focus:border-green-300 px-2 py-2 outline-none",
      ),
      a.id("focus-input"),
      a.value(search),
      // a.autofocus(True),
      a.attribute("autocomplete", "off"),
      a.attribute("autofocus", "true"),
      event.on_keydown(session.KeyDown),
      event.on_input(session.UpdateInput),
    ]),
    h.hr([a.class("mx-40 my-3 border-green-700")]),
    ..list.index_map(suggestions, fn(name, i) {
      h.div(
        [a.class("px-4 py-2 flex"), a.classes([#("bg-gray-800", i == index)])],
        // event.on_click(state.Do(apply)),
        [h.span([], [text(name)]), h.span([a.class("flex-grow")], [])],
      )
    })
  ])
  // h.span([], case shortkey {
  //   Some(k) -> [
  //     h.span(
  //       [
  //         a.class(
  //           "border rounded w-5 leading-snug inline-block font-mono text-center",
  //         ),
  //       ],
  //       [text(k)],
  //     ),
  //   ]
  //   None -> []
  // }),
}

pub fn string_input(value) {
  h.form([event.on_submit(session.DoIt)], [
    h.div([a.class("w-full p-2")], []),
    h.input([
      a.class(
        "block w-full bg-transparent border-l-8 border-green-700 focus:border-green-300 px-2 py-2 outline-none",
      ),
      a.id("focus-input"),
      a.value(value),
      a.attribute("autofocus", "true"),
      event.on_keydown(session.KeyDown),
      event.on_input(session.UpdateInput),
    ]),
    h.hr([a.class("mx-40 my-3 border-green-700")]),
  ])
}

pub fn integer_input(value) {
  h.form([event.on_submit(session.DoIt)], [
    h.div([a.class("w-full p-2")], []),
    h.input([
      a.class(
        "block w-full bg-transparent border-l-8 border-green-700 focus:border-green-300 px-2 py-2 outline-none",
      ),
      a.id("focus-input"),
      a.type_("number"),
      a.value(int.to_string(value)),
      a.attribute("autofocus", "true"),
      event.on_keydown(session.KeyDown),
      event.on_input(session.UpdateInput),
    ]),
    h.hr([a.class("mx-40 my-3 border-green-700")]),
  ])
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
