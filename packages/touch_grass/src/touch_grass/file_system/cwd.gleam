import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v

pub const label = "CWD"

pub fn lift() {
  t.unit
}

pub fn lower() {
  t.result(t.String, t.unit)
}

pub fn decode(input) {
  cast.as_unit(input, Nil)
}

pub fn encode(result) {
  case result {
    Ok(path) -> v.ok(v.String(path))
    Error(reason) -> v.error(v.String(reason))
  }
}
