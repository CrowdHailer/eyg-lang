import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/int
import gleam/javascript/promise
import gleam/result
import plinth/browser/window

pub const l = "Flip"

pub const lift = t.unit

pub fn reply() {
  t.boolean
}

pub fn type_() {
  #(l, #(lift, reply()))
}

pub fn impl(lift) {
  use Nil <- result.try(cast.as_unit(lift, Nil))
  Ok(boolean_to_eyg(do(Nil)))
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn do(_: Nil) {
  case int.random(2) {
    0 -> False
    1 -> True
    _ -> panic as "integer outside expected range"
  }
}

pub fn boolean_to_eyg(result) {
  case result {
    True -> v.true
    False -> v.false
  }
}
