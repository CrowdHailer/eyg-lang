import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast

pub const label = "Prompt"

pub fn lift() {
  t.String
}

pub fn lower() {
  t.result(t.String, t.unit)
}

pub fn decode(lift) {
  cast.as_string(lift)
}
