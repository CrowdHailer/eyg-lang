import eyg/interpreter/cast
import eyg/interpreter/value as v

pub const decode = cast.as_string

pub fn encode(result) {
  case result {
    Ok(data) -> v.ok(v.Binary(data))
    Error(reason) -> v.error(v.String(reason))
  }
}
