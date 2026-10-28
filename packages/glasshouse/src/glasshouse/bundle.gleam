//// Portable, verified closure of an immutable root. The same blocks can instead
//// live in a shared store; this JSON representation is an interchange format.

import glasshouse/store.{type Sha256, type Store}
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

pub type Bundle {
  Bundle(root: String, store: Store)
}

pub fn new(root: String, store: Store) -> Bundle {
  Bundle(root, store.take(store, store.reachable(store, [root])))
}

pub fn validate(bundle: Bundle, sha256: Sha256) -> Result(Bundle, String) {
  case store.corrupt(bundle.store, sha256) {
    [_, ..] -> Error("bundle contains corrupt blocks")
    [] ->
      case
        store.missing(
          bundle.store,
          store.reachable(bundle.store, [bundle.root]),
        )
      {
        [] -> Ok(bundle)
        [_, ..] -> Error("bundle has missing dependencies")
      }
  }
}

pub fn to_string(bundle: Bundle) -> String {
  json.object([
    #("bundle", json.int(1)),
    #("root", json.string(bundle.root)),
    #(
      "blocks",
      store.to_list(bundle.store)
        |> list.map(fn(entry) {
          let assert Ok(text) = bit_array.to_string(entry.1)
          #(entry.0, json.string(text))
        })
        |> json.object,
    ),
  ])
  |> json.to_string
}

pub fn from_string(text: String, sha256: Sha256) -> Result(Bundle, String) {
  let decoder = {
    use version <- decode.field("bundle", decode.int)
    use root <- decode.field("root", decode.string)
    use blocks <- decode.field(
      "blocks",
      decode.dict(decode.string, decode.string),
    )
    case version {
      1 ->
        decode.success(Bundle(
          root,
          dict.map_values(blocks, fn(_, text) { bit_array.from_string(text) }),
        ))
      _ -> decode.failure(Bundle("", store.new()), "bundle version 1")
    }
  }
  json.parse(text, decoder)
  |> result.replace_error("invalid bundle")
  |> result.try(validate(_, sha256))
}
