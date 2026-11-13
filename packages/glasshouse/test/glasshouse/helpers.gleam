import gleam/crypto

pub fn sha256(bytes: BitArray) -> BitArray {
  crypto.hash(crypto.Sha256, bytes)
}
