import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result.{try}
import midas/browser

pub const l = "Visit"

pub const lift = t.String

pub fn reply() {
  t.result(t.unit, t.String)
}

pub fn type_() {
  #(l, #(lift, reply()))
}

pub fn impl(url) {
  use url <- try(cast.as_string(url))
  let frame = #(600, 700)
  let reply = case browser.open(url, frame) {
    Ok(_popup) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
  Ok(reply)
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}
