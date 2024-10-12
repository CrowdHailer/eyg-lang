import lustre/attribute as a
import lustre/element
import lustre/element/html as h

fn header_button(target, text) {
  h.a([a.class("p-1 border-b border-black"), a.href(target)], [
    element.text(text),
  ])
}

pub fn header() {
  h.header([a.class("hstack gap-8 p-2 bg-black text-yellow-2")], [
    h.a([a.class("font-bold text-4xl"), a.href("/")], [element.text("EYG")]),
    header_button("/documentation", "Documentation"),
    header_button("/news", "News"),
  ])
}

pub fn card(children) {
  h.div(
    [
      a.class(
        "border border-white bg-gray-100 rounded-lg overflow-hidden shadow-xl",
      ),
    ],
    children,
  )
}

pub fn keycap(letter) {
  h.span(
    [
      a.style([
        #("box-shadow", "1px 1px 0px 2px black"),
        #("font-size", "85%"),
        #("font-weight", "bold"),
        #("border-radius", "3px"),
        #("margin", "0 5px"),
        #("width", "19px"),
        #("display", "inline-block"),
        #("text-align", "center"),
      ]),
    ],
    [element.text(letter)],
  )
}
