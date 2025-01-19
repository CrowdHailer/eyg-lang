import lustre/attribute as a
import lustre/element/html as h
import morph/lustre/frame

pub fn focus() {
  [
    a.style([
      #("padding", ".25rem"),
      #("background-color", "rgb(167, 243, 208)"),
      #("border-radius", ".25rem"),
      #("margin", "-.25rem"),
    ]),
  ]
}

pub fn error() {
  [a.style([#("text-decoration", "underline red wavy")])]
}

pub fn frame(frame, attributes) {
  case frame {
    frame.Inline(text) -> frame.Inline([spans(text, attributes)])
    frame.Multiline(pre, inner, post) -> {
      frame.Multiline([spans(pre, attributes)], [h.div(attributes, inner)], [
        spans(post, attributes),
      ])
    }
    frame.Statements(inner) -> frame.Statements([h.div(attributes, inner)])
  }
}

pub fn spans(spans, attributes) {
  h.span(attributes, spans)
}
