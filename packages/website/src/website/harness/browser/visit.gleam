import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result.{try}
import midas/browser

fn impl(lift) {
  use url <- try(cast.as_string(lift))
  Ok(do(url))
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

fn do(url) {
  let frame = #(600, 700)
  case browser.open(url, frame) {
    Ok(_popup) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}
