import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/option

pub const label = "Env"

pub fn lift() {
  t.String
}

pub fn lower() {
  t.option(t.String)
}

pub const decode = cast.as_string

pub fn encode(value: option.Option(String)) {
  case value {
    option.Some(s) -> v.some(v.String(s))
    option.None -> v.none()
  }
}
