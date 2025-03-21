import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/window

pub const l = "Alert"

pub const lift = t.String

pub const reply = t.unit

pub fn type_() {
  #(l, #(lift, reply))
}

fn impl(lift) {
  use message <- result.try(cast.as_string(lift))
  let Nil = do(message)
  Ok(v.unit())
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn preflight(lift) {
  use message <- result.try(cast.as_string(lift))
  Ok(fn() {
    let Nil = do(message)
    promise.resolve(v.unit())
  })
}

pub fn do(message) {
  window.alert(message)
}
