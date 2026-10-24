import lustre/attribute as a
import lustre/element/html as h
import morph/lustre/frame

pub fn focus() {
  [
    a.styles([
      #("padding", ".25rem"),
      #("background-color", "rgb(167, 243, 208)"),
      #("border-radius", ".25rem"),
      #("margin", "-.25rem"),
    ]),
  ]
}

pub fn error() {
  [a.styles([#("text-decoration", "underline red wavy")])]
}

pub fn frame(frame, attributes) {
  case frame {
    frame.Inline(text) -> frame.Inline([spans(text, attributes)])
    frame.Multiline(pre, inner, post) -> {
      frame.Multiline(
        boundary(pre, attributes),
        [h.div(attributes, inner)],
        boundary(post, attributes),
      )
    }
    frame.Statements(inner) -> frame.Statements([h.div(attributes, inner)])
  }
}

fn boundary(content, attributes) {
  // Empty boundaries let frame.to_fat_line render the body without indentation.
  case content {
    [] -> []
    _ -> [spans(content, attributes)]
  }
}

pub fn spans(spans, attributes) {
  h.span(attributes, spans)
}
