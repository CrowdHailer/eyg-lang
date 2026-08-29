//// Read everything given to the program on standard input.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v

pub const label = "StandardIn"

pub fn lift() {
  t.unit
}

pub fn lower() {
  t.result(t.Binary, t.String)
}

pub fn decode(input) {
  cast.as_unit(input, Nil)
}

pub fn encode(result) {
  case result {
    Ok(bytes) -> v.ok(v.Binary(bytes))
    Error(reason) -> v.error(v.String(reason))
  }
}
