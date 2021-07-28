pub fn key_find(list: List(#(a, b)), search: a) -> Result(b, Nil) {
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

// Polymorphic functions in Gleam not working without annotation
pub fn map(input: List(a), func: fn(a) -> b) -> List(b) {
  do_map(input, func, [])
}

fn do_map(remaining, func, accumulator) {
  case remaining {
    [] -> reverse(accumulator)
    [item, ..remaining] -> do_map(remaining, func, [func(item), ..accumulator])
  }
}

pub fn fold(input: List(a), initial: b, func: fn(a, b) -> b) -> b {
  case input {
    [] -> initial
    [item, ..rest] -> fold(rest, func(item, initial), func)
  }
}


pub fn zip(left: List(a), right: List(b)) -> Result(List(#(a, b)), Nil) {
  do_zip(left, right, [])
}

fn do_zip(left, right, acc) {
  case left, right {
    [], [] -> Ok(reverse(acc))
    [a, ..left], [b, ..right] -> do_zip(left, right, [#(a, b), ..acc])
    _, _ -> Error(Nil)
  }
}