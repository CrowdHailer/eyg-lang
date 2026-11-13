//// Convert between JSON and EYG values for the HTTP API.
////
//// Objects are records, arrays are lists and booleans are `True({})` and `False({})`.
//// Other tagged values are objects with one key, `Ok(1)` is `{"Ok": 1}`.

import cloud/data
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string

pub fn decoder() -> decode.Decoder(data.Value) {
  decode.one_of(decode.string |> decode.map(data.string), [
    decode.int |> decode.map(data.int),
    decode.bool |> decode.map(data.bool),
    decode.list(decode.recursive(decoder)) |> decode.map(data.list),
    decode.dict(decode.string, decode.recursive(decoder))
      |> decode.map(fn(fields) { data.record(dict.to_list(fields)) }),
    decode.success(v.unit()),
  ])
}

pub fn to_json(value: data.Value) -> json.Json {
  case value {
    v.String(s) -> json.string(s)
    v.Integer(i) -> json.int(i)
    v.Binary(b) -> json.string(bit_array.base64_encode(b, True))
    v.LinkedList(items) -> json.array(items, to_json)
    v.Record(fields) ->
      dict.to_list(fields)
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.map(fn(field) { #(field.0, to_json(field.1)) })
      |> json.object
    v.Tagged("True", v.Record(_)) -> json.bool(True)
    v.Tagged("False", v.Record(_)) -> json.bool(False)
    v.Tagged(tag, inner) -> json.object([#(tag, to_json(inner))])
    v.Closure(..) | v.Partial(..) -> json.string("<function>")
  }
}
