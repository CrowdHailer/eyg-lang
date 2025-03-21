import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/clipboard

pub const l = "Paste"

pub const lift = t.unit

pub fn reply() {
  t.result(t.String, t.String)
}

pub fn type_() {
  #(l, #(lift, reply()))
}

pub fn blocking(lift) {
  use Nil <- result.try(cast.as_unit(lift, Nil))
  Ok(promise.map(do(), result_to_eyg))
}

pub fn preflight(lift) {
  use Nil <- result.try(cast.as_unit(lift, Nil))
  Ok(fn() { promise.map(do(), result_to_eyg) })
}

pub fn non_blocking(lift) {
  use p <- result.try(blocking(lift))
  Ok(v.Promise(p))
}

pub fn do() {
  clipboard.read_text()
}

pub fn result_to_eyg(result) {
  case result {
    Ok(value) -> v.ok(v.String(value))
    Error(reason) -> v.error(v.String(reason))
  }
}
