//// Keep epoch seconds separate from nanoseconds: JS Int cannot hold epoch ns.

import gleam/int
import gleam/result
import gleam/string

pub type Time {
  Time(seconds: Int, nanoseconds: Int)
}

/// The current time, from the high resolution clock on JavaScript and the system clock on Erlang.
pub fn now() -> Time {
  let #(seconds, nanoseconds) = system_time()
  Time(seconds, nanoseconds)
}

@external(erlang, "otel_ffi", "system_time")
@external(javascript, "../otel_ffi.mjs", "system_time")
fn system_time() -> #(Int, Int)

pub fn difference(end: Time, start: Time) -> Int {
  { end.seconds - start.seconds }
  * 1_000_000_000
  + end.nanoseconds
  - start.nanoseconds
}

/// Convert recorded epoch milliseconds without creating an imprecise epoch-ns integer.
pub fn from_milliseconds(value: Int) -> Time {
  Time(value / 1000, { value % 1000 } * 1_000_000)
}

pub fn encode(time: Time) -> String {
  int.to_string(time.seconds)
  <> string.pad_start(int.to_string(time.nanoseconds), 9, "0")
}

pub fn decode(value: String) -> Result(Time, Nil) {
  let length = string.length(value)
  let boundary = int.max(0, length - 9)
  let seconds = string.slice(value, 0, boundary)
  let nanos = string.drop_start(value, boundary)
  use seconds <- result.try(case seconds {
    "" -> Ok(0)
    _ -> int.parse(seconds)
  })
  use nanos <- result.try(int.parse(nanos))
  case seconds >= 0 && nanos >= 0 && nanos < 1_000_000_000 {
    True -> Ok(Time(seconds, nanos))
    False -> Error(Nil)
  }
}
