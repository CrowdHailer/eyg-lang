//// Generate a cryptographic key pair.
////
//// Modelled on the WebCrypto `SubtleCrypto.generateKey` API. The request names
//// the algorithm as a variant and the result carries
//// the exported key material tagged with the same algorithm.
////
//// The request variant is `[Eddsa(opts)]` it can be extended while maintaining compatibility
//// Currently only EdDSA (Ed25519) is supported.
////
//// The exported key follows the JSON Web Key (JWK) shape for an OKP key `Eddsa({ kty, crv, x, d })`,
//// where `x` is the raw public key and `d` the raw private seed (as binaries
//// rather than base64url strings).

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict

pub const label = "CreateKey"

/// The requested key algorithm.
pub type Algorithm {
  Eddsa
}

/// An exported key pair.
pub type Key {
  EddsaKey(public_key: BitArray, private_key: BitArray)
}

pub fn lift() {
  // [Eddsa({}) | ..]
  t.union([#("Eddsa", t.unit)])
}

pub fn lower() {
  t.result(key(), t.String)
}

pub fn key() {
  t.union([#("Eddsa", eddsa_key())])
}

fn eddsa_key() {
  t.record([
    #("kty", t.String),
    #("crv", t.String),
    #("x", t.Binary),
    #("d", t.Binary),
  ])
}

pub fn decode(lift) {
  // Options are accepted but ignored; Ed25519 takes no algorithm parameters.
  cast.as_varient(lift, [#("Eddsa", fn(_opts) { Ok(Eddsa) })])
}

pub fn encode(result: Result(Key, String)) -> v.Value(m, c) {
  case result {
    Ok(key) -> v.ok(encode_key(key))
    Error(message) -> v.error(v.String(message))
  }
}

pub fn encode_key(key: Key) -> v.Value(m, c) {
  case key {
    EddsaKey(public_key:, private_key:) ->
      v.Tagged(
        "Eddsa",
        v.Record(
          dict.from_list([
            #("kty", v.String("OKP")),
            #("crv", v.String("Ed25519")),
            #("x", v.Binary(public_key)),
            #("d", v.Binary(private_key)),
          ]),
        ),
      )
  }
}
