import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/int

pub const label = "Flip"

pub fn lift() {
  t.unit
}

pub fn lower() {
  t.boolean
}

pub fn decode(input) {
  cast.as_unit(input, Nil)
}

pub fn encode(value) {
  v.bool(value)
}

pub fn sync() {
  int.random(2) |> int.is_even
}
