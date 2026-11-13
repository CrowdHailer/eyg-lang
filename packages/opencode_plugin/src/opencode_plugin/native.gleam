//// Plain SDK objects and method calls.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/result
import plinthx/javascript/foreign

pub fn data(value: a) -> Dynamic {
  foreign.to_dynamic(value)
}

pub fn object(fields) {
  foreign.object(array.from_list(fields))
}

pub fn array(values) {
  data(array.from_list(values))
}

pub fn call(target, name, arguments) {
  foreign.call(target, name, array.from_list(arguments))
}

pub fn fail(reason: String) {
  foreign.raise(foreign.error(reason))
}

pub fn field(value, name) {
  decode.run(value, decode.field(name, decode.dynamic, decode.success))
  |> result.unwrap(data(Nil))
}

pub fn text(value) {
  decode.run(value, decode.string) |> result.unwrap("")
}

pub fn string(value, name) {
  text(field(value, name))
}

pub fn fields(value) {
  decode.run(value, decode.dict(decode.string, decode.dynamic))
  |> result.unwrap(dict.new())
}

pub fn list(value) {
  decode.run(value, decode.list(decode.dynamic)) |> result.unwrap([])
}

pub fn with_fields(value, extra) {
  dict.merge(fields(value), dict.from_list(extra)) |> dict.to_list |> object
}
