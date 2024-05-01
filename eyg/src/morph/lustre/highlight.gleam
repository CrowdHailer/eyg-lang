import lustre/attribute as a
import lustre/element/html as h
import morph/lustre/frame

pub fn frame(frame) {
  case frame {
    frame.Inline(text) -> frame.Inline([spans(text)])
    frame.Multiline(pre, inner, post) -> {
      frame.Multiline(
        [h.span([a.class("border-indigo-600 border-b rounded")], pre)],
        [
          h.div(
            [a.class("border-indigo-600 border-b rounded"), a.id("highlighted")],
            inner,
          ),
        ],
        [h.span([a.class("border-indigo-600 border-b rounded")], post)],
      )
    }
    frame.Statements(inner) ->
      frame.Statements([
        h.div(
          [a.class("border-indigo-600 border-b rounded"), a.id("highlighted")],
          inner,
        ),
      ])
  }
}

pub fn spans(spans) {
  h.span(
    [a.class("border-indigo-600 border-b rounded"), a.id("highlighted")],
    spans,
  )
}
