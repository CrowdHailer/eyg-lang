import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/window
import touch_grass/prompt

pub fn run(message) {
  promise.resolve(result_to_eyg(do(message)))
}

fn impl(lift) {
  use message <- result.try(prompt.decode(lift))
  Ok(result_to_eyg(do(message)))
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn preflight(lift) {
  use message <- result.try(prompt.decode(lift))
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
