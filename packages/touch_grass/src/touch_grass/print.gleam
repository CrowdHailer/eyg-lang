import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/io

pub const label = "Print"

pub fn lift() {
  t.String
}

pub fn lower() {
  t.unit
}

pub const decode = cast.as_string

pub fn encode(_: Nil) {
  v.unit()
}

pub fn sync(message) {
  io.print(message)
}
