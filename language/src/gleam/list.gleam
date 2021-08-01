// This should probably be contains
pub fn find(list: List(a), search: a) -> Result(a, Nil) {
  case list {
    [] -> Error(Nil)
    [value, .._] if value == search -> Ok(value)
    [_, ..rest] -> find(rest, search)
  }
}

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

pub fn length(list: List(a)) -> Int {
  fold(list, 0, fn(_, count) { count + 1 })
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

pub fn try_fold(
  input: List(a),
  initial: b,
  func: fn(a, b) -> Result(b, c),
) -> Result(b, c) {
  case input {
    [] -> Ok(initial)
    [item, ..rest] -> {
      try item = func(item, initial)
      try_fold(rest, item, func)
    }
  }
}

pub fn zip(left: List(a), right: List(b)) -> Result(List(#(a, b)), #(Int, Int)) {
  do_zip(left, right, [], 0)
}

fn do_zip(left, right, acc, count) {
  case left, right {
    [], [] -> Ok(reverse(acc))
    [a, ..left], [b, ..right] ->
      do_zip(left, right, [#(a, b), ..acc], count + 1)
    left, right -> Error(#(count + length(left), count + length(right)))
  }
}
