import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/result.{try}
import platforms/browser/windows

pub fn impl(url) {
  use url <- try(cast.as_string(url))
  let frame = #(600, 700)
  let assert Ok(_popup) = windows.open(url, frame)
  Ok(v.unit)
}
