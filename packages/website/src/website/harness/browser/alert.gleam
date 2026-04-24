import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/window
import touch_grass/print

pub fn run(message) {
  let Nil = do(message)
  promise.resolve(v.unit())
}

fn impl(lift) {
  use message <- result.try(print.decode(lift))
  let Nil = do(message)
  Ok(v.unit())
}

pub fn blocking(lift) {
  use value <- result.map(impl(lift))
  promise.resolve(value)
}

pub fn do(message) {
  window.alert(message)
}
