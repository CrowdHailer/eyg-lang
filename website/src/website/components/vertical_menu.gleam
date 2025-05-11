//// This component can align to or bottom in a parent container.
//// The width is set by the components and if icons they should all be the same size

import gleam/list
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event

pub fn one_col_menu(display_help, options) {
  [
    // help_menu_button(state),
    // same as grid below
    h.div(
      [
        a.class("grid overflow-y-auto"),
        a.style([#("grid-template-columns", "max-content max-content")]),
      ],
      [
        h.div(
          [a.class("flex flex-col justify-end text-gray-200 py-2")],
          list.map(options, fn(entry) {
            let #(i, text, k) = entry
            button(k, [icon(i, text, display_help)])
          }),
        ),
      ],
    ),
  ]
}

pub fn two_col_menu(display_help, top, active, sub) {
  [
    h.div(
      [
        a.class("grid overflow-y-auto overflow-x-hidden"),
        a.style([#("grid-template-columns", "max-content max-content")]),
      ],
      [
        h.div(
          [a.class("flex flex-col justify-end text-gray-200 py-2")],
          list.map(top, fn(entry) {
            let #(i, text, k) = entry
            h.button(
              [
                a.class("hover:bg-yellow-600 px-2 py-1 rounded-l-lg"),
                a.classes([#("bg-yellow-600", text == active)]),
                event.on_click(k),
              ],
              [icon(i, text, False)],
            )
          }),
        ),
        h.div(
          [
            a.class(
              "flex flex-col justify-end text-gray-200 bg-yellow-600 rounded-lg py-2",
            ),
          ],
          list.map(sub, fn(entry) {
            let #(i, text, k) = entry
            h.button(
              [a.class("hover:bg-yellow-500 px-2 py-1"), event.on_click(k)],
              [icon(i, text, display_help)],
            )
          }),
        ),
      ],
    ),
  ]
}

pub fn button(action, content) {
  h.button(
    [
      a.class("morph button"),
      a.style([
        // #("background", "none"),
        #("outline", "none"),
        #("border", "none"),
        #("padding-left", ".5rem"),
        #("padding-right", ".5rem"),
        #("padding-top", ".25rem"),
        #("padding-bottom", ".25rem"),
        #("cursor", "pointer"),
        // TODO hover color
      ]),
      event.on_click(action),
    ],
    content,
  )
}

pub fn icon(image, text, display_help) {
  h.span(
    [
      a.style([
        #("align-items", "center"),
        #("border-radius", ".25rem"),
        #("display", "flex"),
      ]),
    ],
    [
      h.span(
        [
          a.style([
            #("font-size", "1.25rem"),
            #("line-height", "1.75rem"),
            #("text-align", "center"),
            #("width", "1.5rem"),
            #("height", "1.75rem"),
            #("display", "inline-block"),
          ]),
        ],
        [image],
      ),
      case display_help {
        True ->
          h.span([a.class("ml-2 border-l border-opacity-25 pl-2")], [
            element.text(text),
          ])
        False -> element.none()
      },
    ],
  )
}
