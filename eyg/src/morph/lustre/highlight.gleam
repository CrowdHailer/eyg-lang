import lustre/attribute as a
import lustre/element/html as h
import morph/lustre/frame

pub fn frame(frame) {
  case frame {
    frame.Inline(text) -> frame.Inline([spans(text)])
    frame.Multiline(pre, inner, post) -> {
      frame.Multiline(
        [h.span([a.class("border-green-600 border-2")], pre)],
        [
          h.div(
            [a.class("border-green-600 border-2"), a.id("highlighted")],
            inner,
          ),
        ],
        [h.span([a.class("border-green-600 border-2")], post)],
      )
    }
  }
}

pub fn spans(spans) {
  h.span([a.class("border-green-600 border-2"), a.id("highlighted")], spans)
}
