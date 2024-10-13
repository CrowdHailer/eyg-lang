import lustre/attribute as a
import lustre/element
import lustre/element/html as h

fn header_button(target, text) {
  h.a([a.class("p-1 text-gray-700"), a.href(target)], [element.text(text)])
}

pub fn header() {
  h.header(
    [a.class("hstack gap-8 p-2 fixed bottom-0 border-t-2 bg-white z-10")],
    [
      h.a([a.class("font-bold text-4xl"), a.href("/")], [element.text("EYG")]),
      header_button("/editor", "Editor"),
      header_button("/documentation", "Documentation"),
    ],
  )
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

pub fn vimeo_intro() {
  [
    h.div([a.attribute("style", "padding:75% 0 0 0;position:relative;")], [
      h.iframe([
        a.attribute("title", "New Recording - 10/13/2024, 8:14:28 PM"),
        a.attribute(
          "style",
          "position:absolute;top:0;left:0;width:100%;height:100%;",
        ),
        a.attribute(
          "allow",
          "autoplay; fullscreen; picture-in-picture; clipboard-write",
        ),
        a.attribute("frameborder", "0"),
        a.src(
          "https://player.vimeo.com/video/1019199789?h=3ee4fc598d&badge=0&autopause=0&player_id=0&app_id=58479",
        ),
      ]),
    ]),
    h.script([a.src("https://player.vimeo.com/api/player.js")], ""),
  ]
}
