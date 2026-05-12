import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/time/timestamp

pub const label = "Now"

pub fn lift() {
  t.unit
}

pub fn lower() {
  t.Integer
}

pub fn decode(input) {
  cast.as_unit(input, Nil)
}

pub fn encode(millis: Int) {
  v.Integer(millis)
}

pub fn sync() {
  let timestamp = timestamp.system_time()
  let #(s, ns) = timestamp.to_unix_seconds_and_nanoseconds(timestamp)
  s * 1000 + ns / 1_000_000
}
