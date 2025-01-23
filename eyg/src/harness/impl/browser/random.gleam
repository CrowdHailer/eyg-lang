import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
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

pub fn impl(lift) {
  use Nil <- result.try(cast.as_unit(lift, Nil))
  Ok(v.Integer(do(Nil)))
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn do(_: Nil) {
  int.random(100)
}
