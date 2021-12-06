import gleam/io

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

// same as do reverse??
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

pub fn pop(list: List(a), value: a) -> Result(List(a), Nil) {
  do_pop(list, value, [])
}

fn do_pop(list, value, accumulator) {
  case list {
    [] -> Error(Nil)
    [next, ..list] if next == value -> Ok(do_append(accumulator, list))
    [next, ..list] -> do_pop(list, value, [next, ..accumulator])
  }
}

pub fn key_pop(list: List(#(k, v)), key: k) -> Result(#(v, List(#(k, v))), Nil) {
  do_key_pop(list, key, [])
}

fn do_key_pop(list, key, accumulator) {
  case list {
    [] -> Error(Nil)
    [#(k, v), ..list] if k == key -> Ok(#(v, do_append(accumulator, list)))
    [next, ..list] -> do_key_pop(list, key, [next, ..accumulator])
  }
}

fn do_flatten(lists: List(List(a)), acc: List(a)) -> List(a) {
  case lists {
    [] -> acc
    [l, ..rest] -> do_flatten(rest, append(acc, l))
  }
}

pub fn flatten(lists: List(List(a))) -> List(a) {
  do_flatten(lists, [])
}

pub fn intersperse(list: List(a), delimeter: a) -> List(a) {
  case list {
    [] -> []
    [one, ..rest] -> do_intersperse(rest, delimeter, [one])
  }
}

fn do_intersperse(list, delimeter, accumulator) {
  case list {
    [] -> reverse(accumulator)
    [item, ..list] ->
      do_intersperse(list, delimeter, [item, delimeter, ..accumulator])
  }
}

pub fn try_map_state(
  list: List(a),
  initial: s,
  func: fn(a, s) -> Result(#(b, s), e),
) -> Result(#(List(b), s), e) {
  do_try_map_state(list, initial, func, [])
}

fn do_try_map_state(list, state, func, accumulator) {
  case list {
    [] -> Ok(#(reverse(accumulator), state))
    [item, ..list] -> {
      try #(item, state) = func(item, state)
      let accumulator = [item, ..accumulator]
      do_try_map_state(list, state, func, accumulator)
    }
  }
}

pub fn map_state(
  list: List(a),
  initial: s,
  func: fn(a, s) -> #(b, s),
) -> #(List(b), s) {
  do_map_state(list, initial, func, [])
}

fn do_map_state(list, state, func, accumulator) {
  case list {
    [] -> #(reverse(accumulator), state)
    [item, ..list] -> {
      let #(item, state) = func(item, state)
      let accumulator = [item, ..accumulator]
      do_map_state(list, state, func, accumulator)
    }
  }
}

pub fn drop(from list: List(a), up_to n: Int) -> List(a) {
  case n <= 0 {
    True -> list
    False ->
      case list {
        [] -> []
        [_, ..xs] -> drop(xs, n - 1)
      }
  }
}

fn do_take(list: List(a), n: Int, acc: List(a)) -> List(a) {
  case n <= 0 {
    True -> reverse(acc)
    False ->
      case list {
        [] -> reverse(acc)
        [x, ..xs] -> do_take(xs, n - 1, [x, ..acc])
      }
  }
}

/// Returns a list containing the first given number of elements from the given
/// list.
///
/// If the element has less than the number of elements then the full list is
/// returned.
///
/// This function runs in linear time but does not copy the list.
///
/// ## Examples
///
///    > take([1, 2, 3, 4], 2)
///    [1, 2]
///
///    > take([1, 2, 3, 4], 9)
///    [1, 2, 3, 4]
///
pub fn take(from list: List(a), up_to n: Int) -> List(a) {
  do_take(list, n, [])
}

fn do_try_map(
  list: List(a),
  fun: fn(a) -> Result(b, e),
  acc: List(b),
) -> Result(List(b), e) {
  case list {
    [] -> Ok(reverse(acc))
    [x, ..xs] ->
      case fun(x) {
        Ok(y) -> do_try_map(xs, fun, [y, ..acc])
        Error(error) -> Error(error)
      }
  }
}

/// Takes a function that returns a Result applies it to each element in a
/// given list in tern.
///
/// If the function returns `Ok(new_value)` for all elements in the list then a
/// list of the new values is returned.
///
/// If the function returns `Error(reason)` for any of the elements then it is
/// returned immediately. None of the elements in the list are processed after
/// one returns an `Error`.
///
/// ## Examples
///
///    > try_map([1, 2, 3], fn(x) { Ok(x + 2) })
///    Ok([3, 4, 5])
///
///    > try_map([1, 2, 3], fn(_) { Error(0) })
///    Error(0)
///
///    > try_map([[1], [2, 3]], head)
///    Ok([1, 2])
///
///    > try_map([[1], [], [2]], head)
///    Error(Nil)
///
pub fn try_map(
  over list: List(a),
  with fun: fn(a) -> Result(b, e),
) -> Result(List(b), e) {
  do_try_map(list, fun, [])
}

fn do_filter(list: List(a), fun: fn(a) -> Bool, acc: List(a)) -> List(a) {
  case list {
    [] -> reverse(acc)
    [x, ..xs] -> {
      let new_acc = case fun(x) {
        True -> [x, ..acc]
        False -> acc
      }
      do_filter(xs, fun, new_acc)
    }
  }
}

/// Returns a new list containing only the elements from the first list for
/// which the given functions returns `True`.
///
/// ## Examples
///
///    > filter([2, 4, 6, 1], fn(x) { x > 2 })
///    [4, 6]
///
///    > filter([2, 4, 6, 1], fn(x) { x > 6 })
///    []
///
pub fn filter(list: List(a), for predicate: fn(a) -> Bool) -> List(a) {
  do_filter(list, predicate, [])
}

/// Returns True if the given function returns True for all the elements in
/// the given list. If the function returns False for any of the elements it
/// immediately returns False without checking the rest of the list.
///
/// ## Examples
///
///    > all([], fn(x) { x > 3 })
///    True
///
///    > all([4, 5], fn(x) { x > 3 })
///    True
///
///    > all([4, 3], fn(x) { x > 3 })
///    False
///
pub fn all(in list: List(a), satisfying predicate: fn(a) -> Bool) -> Bool {
  case list {
    [] -> True
    [x, ..rest] -> predicate(x) && all(rest, predicate)
  }
}

/// Returns True if the given function returns True for any the elements in
/// the given list. If the function returns True for any of the elements it
/// immediately returns True without checking the rest of the list.
///
/// ## Examples
///
///    > any([], fn(x) { x > 3 })
///    False
///
///    > any([4, 5], fn(x) { x > 3 })
///    True
///
///    > any([4, 3], fn(x) { x > 4 })
///    False
///
///    > any([3, 4], fn(x) { x > 3 })
///    True
///
pub fn any(in list: List(a), satisfying predicate: fn(a) -> Bool) -> Bool {
  case list {
    [] -> False
    [x, ..rest] -> predicate(x) || any(rest, predicate)
  }
}

fn do_index_map(
  list: List(a),
  fun: fn(Int, a) -> b,
  index: Int,
  acc: List(b),
) -> List(b) {
  case list {
    [] -> reverse(acc)
    [x, ..xs] -> {
      let acc = [fun(index, x), ..acc]
      do_index_map(xs, fun, index + 1, acc)
    }
  }
}

/// Returns a new list containing only the elements of the first list after the
/// function has been applied to each one and their index.
///
/// The index starts at 0, so the first element is 0, the second is 1, and so
/// on.
///
/// ## Examples
///
///    > index_map(["a", "b"], fn(i, x) { #(i, x) })
///    [#(0, "a"), #(1, "b")]
///
pub fn index_map(list: List(a), with fun: fn(Int, a) -> b) -> List(b) {
  do_index_map(list, fun, 0, [])
}
