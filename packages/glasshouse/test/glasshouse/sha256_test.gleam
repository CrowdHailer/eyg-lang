import glasshouse/sha256
import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/string

fn hex(bytes) {
  bit_array.base16_encode(bytes) |> string.lowercase
}

pub fn known_digests_test() {
  assert hex(sha256.hash(<<>>))
    == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  assert hex(sha256.hash(<<"abc">>))
    == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
}

pub fn agrees_with_crypto_test() {
  // Lengths either side of the 55 and 64 byte padding boundaries.
  list.each([1, 55, 56, 63, 64, 65, 119, 120, 1000], fn(length) {
    let bytes = crypto.strong_random_bytes(length)
    assert sha256.hash(bytes) == crypto.hash(crypto.Sha256, bytes)
  })
}

// Slices that do not start on a byte, the expected digest is from Python's hashlib.
pub fn unaligned_bit_arrays_test() {
  let assert <<_:size(3), rest:bits>> = <<0, "hello world", 0:size(5)>>
  let assert <<bytes:bytes-size(12), _:bits>> = rest
  assert hex(sha256.hash(bytes))
    == "1edbcd592499ac1832732c4b22ff4142f20c0b19610be6f4bc2df203bc1950f7"
}
