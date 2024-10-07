import lustre/attribute as a
import lustre/element
import lustre/element/html as h

fn header_button(text) {
  h.span([a.class("p-2")], [element.text(text)])
}

pub fn header() {
  h.header([a.class("hstack gap-8")], [
    h.span([a.class("font-bold")], [element.text("EYG")]),
    header_button("Features"),
    header_button("Documentation"),
    header_button("News"),
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
