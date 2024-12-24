import gleam/bit_array
import lustre/attribute as a
import lustre/element
import lustre/element/html as h

const blacker = "#151515"

// TODO make hstack functions in mysig
// use the text options 
pub fn render() {
  h.body(
    [
      a.style([
        #("margin", "0"),
        #("width", "1200px"),
        #("max-height", "630px"),
        #("height", "100vh"),
        #("display", "flex"),
        #("flex-direction", "column"),
        #("background-color", "white"),
        #("font-family", "\"Outfit\", sans-serif"),
      ]),
    ],
    [
      h.div(
        [
          a.style([
            #("padding", "0 20px"),
            #("flex-grow", "1"),
            #("display", "flex"),
            #("align-items", "center"),
            #("justify-content", "center"),
          ]),
        ],
        [
          h.img([
            a.src("https://eyg.run/assets/pea.webp"),
            a.alt("Penelopea, EYG's mascot"),
            a.style([#("max-width", "460px")]),
          ]),
          h.div([], [
            h.div([a.style([#("color", blacker), #("font-size", "4.5rem")])], [
              element.text("The EYG language"),
              h.div(
                [
                  a.style([
                    #("color", blacker),
                    #("font-size", "3rem"),
                    #("display", "grid"),
                  ]),
                ],
                [
                  h.span([], [element.text("Predictable")]),
                  h.span([], [element.text("Useful")]),
                  h.span([], [element.text("Confident")]),
                ],
              ),
            ]),
          ]),
        ],
      ),
      h.div(
        [a.style([#("height", "90px"), #("background", "rgb(209,250,229)")])],
        [],
      ),
    ],
  )
  |> element.to_document_string
  |> bit_array.from_string
}
