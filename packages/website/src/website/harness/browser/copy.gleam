import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/clipboard
import touch_grass/copy

pub fn run(text) {
  promise.map(do(text), result_to_eyg)
}

pub fn blocking(lift) {
  use text <- result.try(copy.decode(lift))
  Ok(run(text))
}

pub fn preflight(lift) {
  use text <- result.try(copy.decode(lift))
  Ok(fn() { run(text) })
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
