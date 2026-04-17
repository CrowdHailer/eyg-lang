//// Write a file or overwrite an existing file.
//// 
//// The platform will decide if intermediate files will be created.

import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/result.{try}

pub type Input {
  Input(path: String, contents: BitArray)
}

pub fn decode(input) {
  use path <- try(cast.field("path", cast.as_string, input))
  use contents <- try(cast.field("contents", cast.as_binary, input))
  Ok(Input(path:, contents:))
}

pub fn encode(result) {
  case result {
    Ok(Nil) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}
