import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import touch_grass/uri

pub const label = "Visit"

pub fn lift() {
  uri.uri()
}

pub fn lower() {
  t.result(t.unit, t.String)
}

pub const decode = uri.uri_to_gleam

pub fn encode(result) {
  case result {
    Ok(Nil) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}
