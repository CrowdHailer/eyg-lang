//// The message returned by a scheduled EYG function.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/simple_debug
import gleam/result

pub type Payload {
  Code(String)
  Text(String)
}

pub type Message {
  Message(session_id: String, payload: Payload)
}

pub fn type_() {
  t.record([
    #("session_id", t.String),
    #("payload", t.union([#("Code", t.String), #("Text", t.String)])),
  ])
}

pub fn decode(value) {
  let decoded = {
    use session_id <- result.try(cast.field("session_id", cast.as_string, value))
    use payload <- result.map(cast.field(
      "payload",
      fn(value) {
        cast.as_variant(value, [
          #("Code", cast.map(cast.as_string, Code)),
          #("Text", cast.map(cast.as_string, Text)),
        ])
      },
      value,
    ))
    Message(session_id, payload)
  }
  result.map_error(decoded, simple_debug.describe)
}
