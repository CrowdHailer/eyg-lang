//// Computes a cryptographic digest of a binary.

import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/result.{try}

pub type Algorithm {
  Sha256
}

pub type Input {
  Input(algorithm: Algorithm, bytes: BitArray)
}

pub fn decode(lift) {
  use algorithm <- try(cast.field("algorithm", decode_algorithm, lift))
  use bytes <- try(cast.field("bytes", cast.as_binary, lift))
  Ok(Input(algorithm:, bytes:))
}

fn decode_algorithm(value) {
  cast.as_varient(value, [#("SHA256", cast.as_unit(_, Sha256))])
}

pub fn encode(digest: BitArray) -> v.Value(m, c) {
  v.Binary(digest)
}
