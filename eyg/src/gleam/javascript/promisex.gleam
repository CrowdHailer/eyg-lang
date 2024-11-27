import gleam/javascript/promise
import gleam/list

pub fn aside(p, k) {
  promise.map(p, k)
  Nil
}

pub fn sequential(items, f) {
  do_sequential(items, f, [])
}

fn do_sequential(items, f, acc) {
  case items {
    [] -> promise.resolve(list.reverse(acc))
    [i, ..items] ->
      promise.await(f(i), fn(value) { do_sequential(items, f, [value, ..acc]) })
  }
}
