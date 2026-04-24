//// Download is a version of save, but with a name and not a path.
//// A separate effect is a choice instead of using a magic directory in the filesystem.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import gleam/result.{try}

pub const label = "Download"

pub fn lift() {
  t.file
}

pub fn lower() {
  t.unit
}

pub type Input {
  Input(name: String, content: BitArray)
}

pub fn decode(lift) {
  use name <- try(cast.field("name", cast.as_string, lift))
  use content <- try(cast.field("content", cast.as_binary, lift))
  Ok(Input(name, content))
}
