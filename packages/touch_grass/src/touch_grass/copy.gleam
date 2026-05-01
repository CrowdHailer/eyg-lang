//// Put a string value onto the clipboard

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v

pub const label = "Copy"

pub fn lift() {
  t.String
}

pub fn lower() {
  t.result(t.unit, t.String)
}

pub fn type_() {
  #(label, #(lift, lower()))
}

pub fn decode(input) {
  cast.as_string(input)
}

pub fn encode(result) {
  case result {
    Ok(Nil) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}
