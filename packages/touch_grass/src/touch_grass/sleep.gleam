import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v

pub const label = "Sleep"

pub fn lift() {
  t.Integer
}

pub fn lower() {
  t.unit
}

pub fn decode(input) {
  cast.as_integer(input)
}

pub fn encode(_: Nil) {
  v.unit()
}
