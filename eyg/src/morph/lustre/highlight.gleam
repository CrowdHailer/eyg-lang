import lustre/attribute as a
import lustre/element/html as h
import morph/lustre/frame

// pub const focus = "border-indigo-600 border-b rounded"
pub const focus = "bg-green-200 rounded p-1 -m-1"

pub fn error() {
  [a.style([#("text-decoration", "underline red wavy")])]
  // [a.class("orange-gradient")]
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
