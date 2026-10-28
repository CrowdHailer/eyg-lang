import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/string
import sha256

fn hex(bytes) {
  bit_array.base16_encode(bytes) |> string.lowercase
}

pub fn known_digests_test() {
  assert hex(sha256.hash(<<>>))
    == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  assert hex(sha256.hash(<<"abc">>))
    == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
}

pub fn padding_boundaries_test() {
  list.each([1, 55, 56, 63, 64, 65, 119, 120, 1000], fn(length) {
    let bytes = crypto.strong_random_bytes(length)
    assert sha256.hash(bytes) == crypto.hash(crypto.Sha256, bytes)
  })
}

// RFC 4231 cases 1, 2 and 6 include short and over-block-sized keys.
pub fn hmac_vectors_test() {
  let key = list.repeat(<<0x0B>>, 20) |> bit_array.concat
  assert hex(sha256.hmac(key, <<"Hi There">>))
    == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
  assert hex(sha256.hmac(<<"Jefe">>, <<"what do ya want for nothing?">>))
    == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
  let key = list.repeat(<<0xAA>>, 131) |> bit_array.concat
  assert hex(
      sha256.hmac(key, <<
        "Test Using Larger Than Block-Size Key - Hash Key First",
      >>),
    )
    == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
}

pub fn hmac_agrees_with_host_test() {
  list.each([0, 1, 63, 64, 65, 131], fn(length) {
    let key = crypto.strong_random_bytes(length)
    let bytes = crypto.strong_random_bytes(120)
    assert sha256.hmac(key, bytes) == crypto.hmac(bytes, crypto.Sha256, key)
  })
}
