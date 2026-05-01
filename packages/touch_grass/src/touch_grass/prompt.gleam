import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v

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

pub fn encode(result) {
  case result {
    Ok(value) -> v.ok(v.String(value))
    Error(Nil) -> v.error(v.unit())
  }
}
