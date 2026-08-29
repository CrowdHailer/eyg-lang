//// Create a directory and every missing directory above it.
////
//// Writing a file does not create the directory it goes in, so without this
//// effect a program can only write where a directory already exists. Making
//// a directory that is already there succeeds: the requested state already
//// holds.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v

pub const label = "MakeDirectory"

pub fn lift() {
  t.String
}

pub fn lower() {
  t.result(t.unit, t.String)
}

pub const decode = cast.as_string

pub fn encode(result) {
  case result {
    Ok(Nil) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}
