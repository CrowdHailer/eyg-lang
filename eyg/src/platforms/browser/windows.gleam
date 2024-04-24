import euclidean/square
import gleam/int
import gleam/string
import plinth/browser/window

pub fn open(url, frame_size) {
  let space = #(
    window.outer_width(window.self()),
    window.outer_height(window.self()),
  )
  let #(#(offset_x, offset_y), #(inner_x, inner_y)) =
    square.center(frame_size, space)
  let features =
    string.concat([
      "popup",
      ",width=",
      int.to_string(inner_x),
      ",height=",
      int.to_string(inner_y),
      ",left=",
      int.to_string(offset_x),
      ",top=",
      int.to_string(offset_y),
    ])

  window.open(url, "_blank", features)
}
