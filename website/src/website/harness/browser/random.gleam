import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/int
import gleam/javascript/promise
import gleam/result

pub const l = "Random"

pub const lift = t.Integer

pub const lower = t.Integer

pub fn type_() {
  #(l, #(lift, lower))
}

fn impl(lift) {
  use max <- result.try(cast.as_integer(lift))
  Ok(v.Integer(do(max)))
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn preflight(lift) {
  use value <- result.map(impl(lift))
  fn() { promise.resolve(value) }
}

pub fn do(max) {
  int.random(max)
}
