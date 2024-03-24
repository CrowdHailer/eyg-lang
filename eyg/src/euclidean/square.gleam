import gleam/int

pub fn center(inner, outer) {
  let #(inner_x, inner_y) = inner
  let #(outer_x, outer_y) = outer

  let inner_x = int.min(inner_x, outer_x)
  let inner_y = int.min(inner_y, outer_y)

  let offset_x = { outer_x - inner_x } / 2
  let offset_y = { outer_y - inner_y } / 2

  #(#(offset_x, offset_y), #(inner_x, inner_y))
}
