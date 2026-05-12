//// Delete a file at the given path.
////
//// Deleting a file that does not exist is an error, surfaced via the
//// `Result` return type.

import eyg/interpreter/cast
import eyg/interpreter/value as v

pub fn decode(input) {
  cast.as_string(input)
}

pub fn encode(result) {
  case result {
    Ok(Nil) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}
