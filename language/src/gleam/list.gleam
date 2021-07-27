pub fn key_find(list, search) {
  case list {
    [] -> Error(Nil)
    [#(key, value), .._] if key == search -> Ok(value)
    [_, ..rest] -> key_find(rest, search)
  }
}

pub fn reverse(list: List(a)) -> List(a) {
  do_reverse(list, [])
}

fn do_reverse(remaining, accumulator) {
  case remaining {
    [] -> accumulator
    [next, ..rest] -> do_reverse(rest, [next, ..accumulator])
  }
}

pub fn append(first: List(a), second: List(a)) -> List(a) {
  do_append(reverse(first), second)
}

fn do_append(remaining, accumulator) {
  case remaining {
    [] -> accumulator
    [item, ..rest] -> do_append(rest, [item, ..accumulator])
  }
}
