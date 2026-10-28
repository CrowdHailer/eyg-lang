import eyg_pi/frame
import gleam/bit_array
import gleam/list

pub fn rgb_console_cells_ignore_the_cursor_when_requested_test() {
  let black = <<0, 0, 0>>
  let pixels =
    bit_array.concat([
      bit_array.concat(list.repeat(black, 120)),
      <<255, 255, 255>>,
      bit_array.concat(list.repeat(black, 7)),
    ])
  let image = frame.decode(<<"P6\n8 16\n255\n":utf8, pixels:bits>>)
  assert image.width == 8 && image.height == 16
  assert frame.lit(image, 0, 0, False) == 1
  assert frame.lit(image, 0, 0, True) == 0
  assert frame.lit(image, 1, 0, False) == 0
}
