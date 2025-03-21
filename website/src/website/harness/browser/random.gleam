import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/int
import gleam/javascript/promise
import gleam/result

pub const l = "Random"

pub const lift = t.unit

pub fn reply() {
  t.Integer
}

pub fn type_() {
  #(l, #(lift, reply()))
}

fn impl(lift) {
  use Nil <- result.try(cast.as_unit(lift, Nil))
  Ok(v.Integer(do(Nil)))
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn preflight(lift) {
  use value <- result.map(impl(lift))
  fn() { promise.resolve(value) }
}

pub fn do(_: Nil) {
  int.random(100)
}
