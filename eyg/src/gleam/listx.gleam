import gleam/list

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

pub fn value_map(l, f) {
  list.map(l, fn(field) {
    let #(k, v) = field
    #(k, f(v))
  })
}
