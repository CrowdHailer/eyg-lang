import gleam/string
import eyg/runtime/interpreter as r
import harness/ffi/cast

// import harness/ffi/spec.{build, integer, lambda, string}

// pub fn append() {
//   lambda(string(), lambda(string(), string()))
//   |> build(fn(x) { fn(y) { str.append(x, y) } })
// }
pub fn append() {
  r.Arity2(do_append)
}

pub fn do_append(left, right, k) {
  use left <- cast.string(left)
  use right <- cast.string(right)
  r.continue(k, r.Binary(string.append(left, right)))
}
// pub fn uppercase() {
//   lambda(string(), string())
//   |> build(fn(x) { str.uppercase(x) })
// }

// pub fn lowercase() {
//   lambda(string(), string())
//   |> build(fn(x) { str.lowercase(x) })
// }

// pub fn length() {
//   lambda(string(), integer())
//   |> build(fn(x) { str.length(x) })
// }
