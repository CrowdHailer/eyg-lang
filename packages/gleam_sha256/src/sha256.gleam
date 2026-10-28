//// Portable SHA-256 (FIPS 180-4) and HMAC-SHA-256 (RFC 2104).
//// Synchronous Gleam arithmetic on the BEAM and in browsers, Node and Bun.

import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list

const modulus = 4_294_967_296

const constants = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

pub fn hash(bytes: BitArray) -> BitArray {
  let size = bit_array.byte_size(bytes)
  let padding = { 64 - { { size + 9 } % 64 } } % 64
  let zeros = list.repeat(<<0>>, padding) |> bit_array.concat
  let bits = size * 8
  let padded = <<
    bytes:bits,
    0x80,
    zeros:bits,
    { bits / modulus }:size(32),
    { bits % modulus }:size(32),
  >>
  let words =
    blocks(padded, [
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
      0x1f83d9ab, 0x5be0cd19,
    ])
  words |> list.map(fn(word) { <<word:size(32)>> }) |> bit_array.concat
}

/// Authenticate `message` with `key`, returning the full 32-byte digest.
pub fn hmac(key: BitArray, message: BitArray) -> BitArray {
  let key = case bit_array.byte_size(key) > 64 {
    True -> hash(key)
    False -> key
  }
  let padding =
    list.repeat(<<0>>, 64 - bit_array.byte_size(key))
    |> bit_array.concat
  let key = <<key:bits, padding:bits>>
  let inner = xor_bytes(key, 0x36, <<>>)
  let outer = xor_bytes(key, 0x5C, <<>>)
  let digest = hash(<<inner:bits, message:bits>>)
  hash(<<outer:bits, digest:bits>>)
}

fn xor_bytes(bytes, pad, acc) {
  case bytes {
    <<byte, rest:bytes>> ->
      xor_bytes(rest, pad, <<acc:bits, int.bitwise_exclusive_or(byte, pad)>>)
    _ -> acc
  }
}

fn rotate(value, bits) {
  int.bitwise_or(
    int.bitwise_shift_right(value, bits),
    int.bitwise_shift_left(value, 32 - bits) % modulus,
  )
}

fn xor3(a, b, c) {
  int.bitwise_exclusive_or(int.bitwise_exclusive_or(a, b), c)
}

fn blocks(bytes, state) {
  case bytes {
    <<block:bytes-size(64), rest:bytes>> -> {
      let schedule = initial_words(block, dict.new(), 0) |> expand(16)
      let rounds =
        list.index_fold(constants, state, fn(state, constant, i) {
          let assert [a, b, c, d, e, f, g, h] = state
          let assert Ok(word) = dict.get(schedule, i)
          let choose =
            int.bitwise_exclusive_or(
              int.bitwise_and(e, f),
              int.bitwise_and(int.bitwise_not(e), g),
            )
          let t1 =
            {
              h
              + xor3(rotate(e, 6), rotate(e, 11), rotate(e, 25))
              + choose
              + constant
              + word
            }
            % modulus
          let majority =
            xor3(
              int.bitwise_and(a, b),
              int.bitwise_and(a, c),
              int.bitwise_and(b, c),
            )
          let t2 =
            { xor3(rotate(a, 2), rotate(a, 13), rotate(a, 22)) + majority }
            % modulus
          [{ t1 + t2 } % modulus, a, b, c, { d + t1 } % modulus, e, f, g]
        })
      let next = list.map2(state, rounds, fn(a, b) { { a + b } % modulus })
      blocks(rest, next)
    }
    <<>> -> state
    _ -> panic as "invalid SHA-256 padding"
  }
}

fn initial_words(bytes, words, i) {
  case bytes {
    <<word:size(32), rest:bytes>> ->
      initial_words(rest, dict.insert(words, i, word), i + 1)
    _ -> words
  }
}

fn expand(words, i) {
  case i == 64 {
    True -> words
    False -> {
      let assert Ok(a) = dict.get(words, i - 15)
      let assert Ok(b) = dict.get(words, i - 2)
      let assert Ok(c) = dict.get(words, i - 16)
      let assert Ok(d) = dict.get(words, i - 7)
      let s0 = xor3(rotate(a, 7), rotate(a, 18), int.bitwise_shift_right(a, 3))
      let s1 =
        xor3(rotate(b, 17), rotate(b, 19), int.bitwise_shift_right(b, 10))
      expand(dict.insert(words, i, { c + s0 + d + s1 } % modulus), i + 1)
    }
  }
}
