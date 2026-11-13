//// Mount a retained immutable artifact at a new path. Existing entries are
//// never replaced: delete explicitly or choose another path.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/result

pub const label = "Mount"

pub type Input {
  Input(root: String, path: String)
}

pub fn lift() {
  t.record([#("root", t.String), #("path", t.String)])
}

pub fn lower() {
  t.result(t.unit, t.String)
}

pub fn decode(value) {
  use root <- result.try(cast.field("root", cast.as_string, value))
  use path <- result.map(cast.field("path", cast.as_string, value))
  Input(root, path)
}

pub fn encode(reply: Result(Nil, String)) -> v.Value(m, c) {
  case reply {
    Ok(_) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}
