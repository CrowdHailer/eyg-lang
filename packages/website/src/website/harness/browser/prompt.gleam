import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
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

pub fn cast(lift) {
  cast.as_string(lift)
}

pub fn run(message) {
  promise.resolve(result_to_eyg(do(message)))
}

fn impl(lift) {
  use message <- result.try(cast(lift))
  Ok(result_to_eyg(do(message)))
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn preflight(lift) {
  use message <- result.try(cast(lift))
  Ok(fn() { promise.resolve(result_to_eyg(do(message))) })
}

pub fn do(message) {
  window.prompt(message)
}

pub fn result_to_eyg(result) {
  case result {
    Ok(value) -> v.ok(v.String(value))
    Error(Nil) -> v.error(v.unit())
  }
}
