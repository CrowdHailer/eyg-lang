import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/result
import plinth/javascript/date

pub const l = "Now"

pub const lift = t.unit

pub const reply = t.String

pub fn type_() {
  #(l, #(lift, reply))
}

pub fn impl(lift) {
  use Nil <- result.try(cast.as_unit(lift, Nil))
  Ok(v.String(do()))
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn do() {
  let now = date.now()
  date.to_iso_string(now)
}
