import gleam/list
import lustre/element
import lustre/element/html as h
import morph/lustre/frame
import morph/lustre/highlight

pub fn highlighting_borderless_multiline_does_not_add_indentation_test() {
  let inner = [
    h.div([], [element.text("first")]),
    h.div([], [element.text("last")]),
  ]

  list.each([highlight.focus(), highlight.error()], fn(attributes) {
    let rendered =
      frame.Multiline([], inner, [])
      |> highlight.frame(attributes)
      |> frame.to_fat_line
      |> element.to_string

    let expected =
      h.div([], [h.div(attributes, inner)])
      |> element.to_string

    assert rendered == expected
  })
}
