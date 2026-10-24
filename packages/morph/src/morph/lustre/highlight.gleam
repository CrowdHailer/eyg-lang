import gleam/list

// import lustre/attribute as a

import morph/lustre/frame

pub fn focus() {
  // [
  //   a.styles([
  //     #("padding", ".25rem"),
  //     #("background-color", "rgb(167, 243, 208)"),
  //     #("border-radius", ".25rem"),
  //     #("margin", "-.25rem"),
  //   ]),
  // ]
  Focus
}

pub fn error() {
  // [a.styles([#("text-decoration", "underline red wavy")])]
  Error
}

pub fn frame(f, highlight) {
  case f {
    frame.Inline(text) -> frame.Inline(spans(text, highlight))
    frame.Multiline(pre, inner, post) -> {
      frame.Multiline(
        spans(pre, highlight),
        list.map(inner, frame(_, highlight)),
        spans(post, highlight),
      )
    }
    frame.Statements(inner) ->
      frame.Statements(list.map(inner, frame(_, highlight)))
  }
}

pub type Highlight {
  Focus
  Error
}

pub fn spans(spans: List(frame.Span), highlight) {
  list.map(spans, fn(span) {
    case highlight {
      Focus -> frame.Span(..span, focus: True)
      Error -> frame.Span(..span, error: True)
    }
  })
}
