import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/clipboard

pub const l = "Copy"

pub const lift = t.String

pub fn reply() {
  t.result(t.unit, t.String)
}

pub fn type_() {
  #(l, #(lift, reply()))
}

pub fn blocking(lift) {
  use message <- result.try(cast.as_string(lift))
  Ok(promise.map(do(message), result_to_eyg))
}

pub fn preflight(lift) {
  use message <- result.try(cast.as_string(lift))
  Ok(fn() { promise.map(do(message), result_to_eyg) })
}

pub fn non_blocking(lift) {
  use p <- result.try(blocking(lift))
  Ok(v.Promise(p))
}

pub fn do(text) {
  clipboard.write_text(text)
}

pub fn result_to_eyg(result) {
  case result {
    Ok(Nil) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}
