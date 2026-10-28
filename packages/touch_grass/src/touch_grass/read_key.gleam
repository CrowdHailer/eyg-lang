//// Read a single key press without waiting for a line of input.
////
//// The argument is how long to wait in milliseconds, `0` checks for a key that was already pressed.
//// Keys are named as in the browser's `KeyboardEvent.key`,
//// i.e. `"a"`, `"A"`, `" "`, `"ArrowUp"`, `"Enter"`, `"Escape"`, `"Backspace"`.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/option

pub const label = "ReadKey"

pub fn lift() {
  t.Integer
}

pub fn lower() {
  t.option(t.String)
}

pub fn decode(input) {
  cast.as_integer(input)
}

pub fn encode(key: option.Option(String)) {
  case key {
    option.Some(key) -> v.some(v.String(key))
    option.None -> v.none()
  }
}
