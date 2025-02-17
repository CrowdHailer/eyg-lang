import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/window

pub const l = "Alert"

pub const lift = t.String

pub const reply = t.unit

pub fn type_() {
  #(l, #(lift, reply))
}

pub fn impl(lift) {
  use message <- result.try(cast.as_string(lift))
  let Nil = do(message)
  Ok(v.unit())
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn do(message) {
  window.alert(message)
}
