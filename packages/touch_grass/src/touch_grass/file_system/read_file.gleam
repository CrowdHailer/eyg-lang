//// Read the contents of a file
//// 
//// Accepts a limit by default, this should be large.
//// The effect doesn't assume a file is kept open and so streaming very large files should be handled as a different effect.

import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/result.{try}

pub type Input {
  Input(path: String, offset: Int, limit: Int)
}

pub fn decode(input) {
  use path <- try(cast.field("path", cast.as_string, input))
  use offset <- try(cast.field("offset", cast.as_integer, input))
  use limit <- try(cast.field("limit", cast.as_integer, input))
  Ok(Input(path:, offset:, limit:))
}

pub fn encode(result) {
  case result {
    Ok(data) -> v.ok(v.Binary(data))
    Error(reason) -> v.error(v.String(reason))
  }
}
