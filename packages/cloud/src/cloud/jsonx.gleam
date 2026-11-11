import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string

/// Preserves JSON values and array order, sorting object keys for stable encoding.
pub fn decoder() -> decode.Decoder(json.Json) {
  decode.one_of(decode.string |> decode.map(json.string), or: [
    decode.int |> decode.map(json.int),
    decode.float |> decode.map(json.float),
    decode.bool |> decode.map(json.bool),
    decode.list(decode.recursive(decoder))
      |> decode.map(json.preprocessed_array),
    decode.dict(decode.string, decode.recursive(decoder))
      |> decode.map(fn(fields) {
        // Stable object-key order makes version comparison independent of the
        // order Slack used when serializing otherwise identical objects.
        fields
        |> dict.to_list
        |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
        |> json.object
      }),
  ])
  |> decode.optional
  |> decode.map(json.nullable(_, fn(x) { x }))
}
