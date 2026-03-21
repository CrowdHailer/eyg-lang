import eyg/interpreter/value as v
import touch_grass/http

pub const decode = http.request_to_gleam

pub fn encode(result) {
  case result {
    Ok(response) -> v.ok(http.response_to_eyg(response))
    Error(reason) -> v.error(v.String(reason))
  }
}
