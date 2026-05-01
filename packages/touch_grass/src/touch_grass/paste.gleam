import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v

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

pub fn encode(result) {
  case result {
    Ok(value) -> v.ok(v.String(value))
    Error(reason) -> v.error(v.String(reason))
  }
}
