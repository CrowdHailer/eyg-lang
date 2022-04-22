import gleam/list

pub fn map_state(
  list: List(a),
  initial: s,
  func: fn(a, s) -> #(b, s),
) -> #(List(b), s) {
  do_map_state(list, initial, func, [])
}

fn do_map_state(list, state, func, accumulator) {
  case list {
    [] -> #(list.reverse(accumulator), state)
    [item, ..list] -> {
      let #(item, state) = func(item, state)
      let accumulator = [item, ..accumulator]
      do_map_state(list, state, func, accumulator)
    }
  }
}

fn do_zip_with(list, state, generator, accumulator) {
  case list {
    [] -> list.reverse(accumulator)
    [item, ..list] -> {
      let #(next, state) = generator(state)
      let accumulator = [#(item, next), ..accumulator]
      do_zip_with(list, state, generator, accumulator)
    }
  }
}

pub fn zip_with(list, state, generator) {
  do_zip_with(list, state, generator, [])
}
