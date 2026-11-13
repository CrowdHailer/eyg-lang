//// Build EYG values from Gleam data.
////
//// Values built here hold no closures, so they are plain trees
//// that can be sent between processes, see `notes/cloud-process-boundaries.md`.

import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/option.{type Option}

pub type Value =
  state.Value(#(Int, Int))

pub fn record(fields: List(#(String, Value))) -> Value {
  v.Record(dict.from_list(fields))
}

pub fn string(value: String) -> Value {
  v.String(value)
}

pub fn int(value: Int) -> Value {
  v.Integer(value)
}

pub fn bool(value: Bool) -> Value {
  case value {
    True -> v.true()
    False -> v.false()
  }
}

pub fn strings(values: List(String)) -> Value {
  v.LinkedList(list.map(values, v.String))
}

pub fn list(values: List(Value)) -> Value {
  v.LinkedList(values)
}

pub fn tagged(tag: String, value: Value) -> Value {
  v.Tagged(tag, value)
}

/// `Some(value)` or `None({})`.
pub fn option(value: Option(a), inner: fn(a) -> Value) -> Value {
  case value {
    option.Some(value) -> v.Tagged("Some", inner(value))
    option.None -> v.Tagged("None", v.unit())
  }
}
