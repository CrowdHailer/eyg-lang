//// Produce a signature over a binary with a private key.
////
//// Modelled on the WebCrypto `SubtleCrypto.sign(algorithm, key, data)` API. The
//// request is a record `{ key, data }` where `key` is a key in the shape
//// produced by a successful `CreateKey` effect (`Eddsa({ kty, crv, x, d })`)
//// and `data` is the binary to sign. The algorithm is taken from the key's
//// variant tag.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/result.{try}
import touch_grass/cryptography/create_key

pub const label = "Sign"

/// A decoded signing request: the algorithm, its private key material and the
/// data to sign.
pub type Request {
  EddsaSign(private_key: BitArray, data: BitArray)
}

pub fn lift() {
  t.record([#("key", create_key.key()), #("data", t.Binary)])
}

pub fn lower() {
  t.result(t.Binary, t.String)
}

pub fn decode(lift) {
  use key <- try(cast.field("key", Ok, lift))
  use data <- try(cast.field("data", cast.as_binary, lift))
  cast.as_varient(key, [
    #("Eddsa", fn(keydata) {
      use d <- try(cast.field("d", cast.as_binary, keydata))
      Ok(EddsaSign(private_key: d, data:))
    }),
  ])
}

pub fn encode(result: Result(BitArray, String)) -> v.Value(m, c) {
  case result {
    Ok(signature) -> v.ok(v.Binary(signature))
    Error(message) -> v.error(v.String(message))
  }
}
