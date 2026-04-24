import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast

pub const label = "Paste"

pub fn lift() {
  t.unit
}

pub fn lower() {
  t.result(t.String, t.String)
}

pub fn decode(lift) {
  cast.as_unit(lift, Nil)
}
