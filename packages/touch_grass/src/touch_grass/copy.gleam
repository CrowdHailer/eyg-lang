//// Put a string value onto the clipboard

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast

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
