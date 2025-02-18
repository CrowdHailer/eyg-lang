import gleam/javascript/promise

pub fn aside(p, k) {
  promise.map(p, k)
  Nil
}
