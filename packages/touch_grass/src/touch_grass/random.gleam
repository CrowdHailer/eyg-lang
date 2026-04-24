import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/int

pub const label = "Random"

pub fn lift() {
  t.Integer
}

pub fn lower() {
  t.Integer
}

pub fn decode(lift) {
  cast.as_integer(lift)
}

pub fn encode(number) {
  v.Integer(number)
}

pub fn sync(max) {
  int.random(max)
}
