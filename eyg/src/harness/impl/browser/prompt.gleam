import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/window

pub const l = "Prompt"

pub const lift = t.String

pub fn reply() {
  t.result(t.String, t.unit)
}

pub fn type_() {
  #(l, #(lift, reply()))
}

pub fn impl(lift) {
  use message <- result.try(cast.as_string(lift))
  Ok(result_to_eyg(do(message)))
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn do(message) {
  window.prompt(message)
}

pub fn result_to_eyg(result) {
  case result {
    Ok(value) -> v.ok(v.Str(value))
    Error(Nil) -> v.error(v.unit)
  }
}
