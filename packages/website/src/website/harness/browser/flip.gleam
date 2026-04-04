import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/int
import gleam/javascript/promise
import gleam/result

pub const l = "Flip"

pub const lift = t.unit

pub fn reply() {
  t.boolean
}

pub fn type_() {
  #(l, #(lift, reply()))
}

fn impl(lift) {
  use Nil <- result.try(cast.as_unit(lift, Nil))
  Ok(boolean_to_eyg(do(Nil)))
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn preflight(lift) {
  use Nil <- result.try(cast.as_unit(lift, Nil))
  Ok(fn() { promise.resolve(boolean_to_eyg(do(Nil))) })
}

pub fn do(_: Nil) {
  case int.random(2) {
    0 -> False
    1 -> True
    _ -> panic as "integer outside expected range"
  }
}

fn boolean_to_eyg(result) {
  case result {
    True -> v.true()
    False -> v.false()
  }
}
