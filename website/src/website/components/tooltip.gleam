import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import website/components/snippet

pub fn inline(spans) {
  h.span([a.class("inline relative")], [above(), below(), ..spans])
}

pub fn block(divs) {
  h.div([a.class("relative")], [above(), below(), ..divs])
}

fn above() {
  h.div(
    [
      a.class("flex gap-2"),
      a.style([
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
          event.on_click(snippet.UserPressedCommandKey("l")),
        ],
        [element.text("[]")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mb-1"),
          event.on_click(snippet.UserPressedCommandKey("r")),
        ],
        [element.text("{}")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mb-1"),
          event.on_click(snippet.UserPressedCommandKey("c")),
        ],
        [element.text("()")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mt-1"),
          event.on_click(snippet.UserPressedCommandKey("f")),
        ],
        [element.text("->")],
      ),
    ],
  )
}

fn below() {
  h.div(
    [
      a.class("flex gap-2"),
      a.style([
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
          event.on_click(snippet.UserPressedCommandKey("s")),
        ],
        [element.text("\"\"")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mt-1"),
          event.on_click(snippet.UserPressedCommandKey("n")),
        ],
        [element.text("5")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mt-1"),
          event.on_click(snippet.UserPressedCommandKey("a")),
        ],
        [element.text("+")],
      ),
      h.span(
        [
          a.class("bg-gray-700 p-1 rounded mb-1"),
          event.on_click(snippet.UserPressedCommandKey("#")),
        ],
        [element.text("@")],
      ),
    ],
  )
}
