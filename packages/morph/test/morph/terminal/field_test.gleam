import etui/buffer
import etui/geometry.{Position}
import etui/style
import etui/widgets/input
import gleam/int
import gleam/list
import morph/terminal/field

fn typed(keys) {
  list.fold(keys, input.state_new(), fn(editing, key) {
    field.edit(input.input_new(""), editing, key)
  })
}

// The column of the reversed cell on the first row.
fn cursor(editing) {
  let area = geometry.rect_new(0, 0, 10, 1)
  let buf =
    field.render(buffer.buffer_new(area), area, input.input_new(""), editing)
  int.range(0, 10, [], fn(acc, x) { [x, ..acc] })
  |> list.reverse
  |> list.filter(fn(x) {
    let cell = buffer.get_cell(buf, Position(x, 0))
    style.has(cell.style.modifier, style.reverse())
  })
}

pub fn move_and_edit_test() {
  assert "acb" == typed(["a", "b", "left", "c"]).value
  assert "xab" == typed(["a", "b", "home", "x"]).value
  assert "a" == typed(["a", "b", "left", "delete"]).value
  assert "" == typed(["a", "b", "ctrl+u"]).value
}

pub fn draw_the_cursor_test() {
  // After the text the cursor is a space, within it the character is reversed.
  assert [2] == cursor(typed(["a", "b"]))
  assert [1] == cursor(typed(["a", "b", "left"]))
  assert [0] == cursor(input.state_new())
  // Text longer than the area is scrolled so the cursor shows.
  assert [9] == cursor(input.state_from_string("abcdefghijklmn"))
}
