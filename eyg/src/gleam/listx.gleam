import gleam/list
import gleam/result

fn do_filter_errors(l, acc) {
  case l {
    [] -> list.reverse(acc)
    [Ok(_), ..rest] -> do_filter_errors(rest, acc)
    [Error(reason), ..rest] -> do_filter_errors(rest, [reason, ..acc])
  }
}

pub fn filter_errors(l) {
  do_filter_errors(l, [])
}

pub fn insert_at(list, position, new) {
  let pre = list.take(list, position)
  let post = list.drop(list, position)
  list.flatten([pre, new, post])
}

pub fn delete_at(items, i) {
  let pre = list.take(items, i)
  let post = list.drop(items, i + 1)
  list.flatten([pre, post])
}

pub fn map_at(items, i, f) {
  use item <- result.then(list.at(items, i))
  let pre = list.take(items, i)
  let post = list.drop(items, i + 1)
  Ok(list.flatten([pre, [f(item)], post]))
}

pub fn keys(pairs) {
  list.map(pairs, fn(pair) {
    let #(key, _value) = pair
    key
  })
}

pub fn value_map(l, f) {
  list.map(l, fn(field) {
    let #(k, v) = field
    #(k, f(v))
  })
}

pub fn move(a, b) {
  case a {
    [] -> b
    [i, ..a] -> move(a, [i, ..b])
  }
}

// TODO move to cleave

pub type Cleave(a) =
  #(List(a), a, List(a))

pub fn split_around(items, at) {
  do_split_around(items, at, [])
}

fn do_split_around(items, left, acc) {
  case items, left {
    // pre is left reversed
    [item, ..after], 0 -> Ok(#(acc, item, after))
    [item, ..after], i -> do_split_around(after, i - 1, [item, ..acc])
    [], _ -> Error(Nil)
  }
}

pub fn gather_around(pre, item, post) {
  move(pre, [item, ..post])
}

pub fn map_cleave(cleave, f) {
  let #(pre, value, post) = cleave
  let pre = list.map(pre, f)
  let value = f(value)
  let post = list.map(post, f)
  #(pre, value, post)
}
