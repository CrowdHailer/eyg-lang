import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event

pub fn inline(spans, user_pressed_command_key) {
  h.span([a.class("inline relative")], [
    above(user_pressed_command_key),
    below(user_pressed_command_key),
    ..spans
  ])
}

pub fn block(divs, user_pressed_command_key) {
  h.div([a.class("relative")], [
    above(user_pressed_command_key),
    below(user_pressed_command_key),
    ..divs
  ])
}

fn above(user_pressed_command_key) {
  h.div(
    [
      a.class("flex gap-2"),
      a.styles([
        #("position", "absolute"),
        // #("background-color", "rgba(0, 0, 0, 0.75)"),
        #("color", "white"),
        // #("padding", "5px 10px"),
        // #("border-radius", "4px"),
        #("font-size", "12px"),
        #("white-space", "nowrap"),
        // #("opacity", "0"),
        // #("visibility", "hidden"),
        #("transition", "opacity 0.3s ease"),

        // 
        // 
        #("bottom", "100%"),
        #("left", "0"),
        #("transform", "translateX(-10%)"),
        #("margin-bottom", "5px"),
      ]),
    ],
    [
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mt-1"),
          event.on_click(user_pressed_command_key("l")),
        ],
        [element.text("[]")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mb-1"),
          event.on_click(user_pressed_command_key("r")),
        ],
        [element.text("{}")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mb-1"),
          event.on_click(user_pressed_command_key("c")),
        ],
        [element.text("()")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mt-1"),
          event.on_click(user_pressed_command_key("f")),
        ],
        [element.text("->")],
      ),
    ],
  )
}

fn below(user_pressed_command_key) {
  h.div(
    [
      a.class("flex gap-2"),
      a.styles([
        #("position", "absolute"),
        // #("background-color", "rgba(0, 0, 0, 0.75)"),
        #("color", "white"),
        // #("padding", "5px 10px"),
        // #("border-radius", "4px"),
        #("font-size", "12px"),
        #("white-space", "nowrap"),
        // #("opacity", "0"),
        // #("visibility", "hidden"),
        #("transition", "opacity 0.3s ease"),
        // 
        #("top", "100%"),
        #("left", "0"),
        #("transform", "translateX(-10%)"),
        #("margin-top", "5px"),
      ]),
    ],
    [
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mb-1"),
          event.on_click(user_pressed_command_key("s")),
        ],
        [element.text("\"\"")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mt-1"),
          event.on_click(user_pressed_command_key("n")),
        ],
        [element.text("5")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mt-1"),
          event.on_click(user_pressed_command_key("a")),
        ],
        [element.text("+")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mb-1"),
          event.on_click(user_pressed_command_key("#")),
        ],
        [element.text("@")],
      ),
    ],
  )
}
