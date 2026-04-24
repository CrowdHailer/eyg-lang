import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/clipboard
import touch_grass/paste

pub fn run() {
  promise.map(do(), result_to_eyg)
}

pub fn blocking(lift) {
  use Nil <- result.try(paste.decode(lift))
  Ok(run())
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
