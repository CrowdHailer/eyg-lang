import gleam/bit_string
import gleam/io
import gleam/result
import eygir/expression as e
import gleeunit/should

pub fn encode_string(label) {
  let binary = bit_string.from_string(label)
  <<bit_string.byte_size(binary), binary:bit_string>>
}

pub fn linear(source) {
  case source {
    e.Variable(label) -> <<1, encode_string(label):bit_string>>
    e.Lambda(label, body) -> <<
      2,
      encode_string(label):bit_string,
      linear(body):bit_string,
    >>
    e.Apply(func, arg) -> <<3, linear(func):bit_string, linear(arg):bit_string>>
    e.Let(label, value, then) -> <<
      4,
      encode_string(label):bit_string,
      linear(value):bit_string,
      linear(then):bit_string,
    >>
    e.Integer(value) -> <<5, value:32>>
    _ -> todo
  }
}

fn decode_label(x, rest) {
  use label <- result.then(bit_string.slice(rest, 0, x))
  use rest <- result.then(bit_string.slice(
    rest,
    x,
    bit_string.byte_size(rest) - x,
  ))
  use label <- result.then(bit_string.to_string(label))
  Ok(#(label, rest))
}

pub fn decode(bytes) {
  case bytes {
    <<1, x, rest:binary>> -> {
      use #(label, rest) <- result.then(decode_label(x, rest))
      Ok(#(e.Variable(label), rest))
    }
    <<4, x, rest:binary>> -> {
      io.debug("matched")
      use #(label, rest) <- result.then(decode_label(x, rest))
      use #(value, rest) <- result.then(decode(rest))
      use #(then, rest) <- result.then(decode(rest))
      Ok(#(e.Let(label, value, then), rest))
    }
    <<5, value:32, rest:binary>> -> Ok(#(e.Integer(value), rest))
    _ -> {
      io.debug(bytes)
      todo("some bytes")
    }
  }
}

external fn log(a) -> Nil =
  "" "console.log"

// hash and digest
external fn hash(BitString) -> String =
  "./node_ffi.js" "hash"

fn gather_hash(source) {
  case source {
    <<1, x, rest:binary>> -> {
      use part <- result.then(bit_string.slice(rest, 0, x))
      Ok(log(hash(<<1, x, part:bit_string>>)))
    }

    // TODO need a pop function that doesn't turn to string, i.e.utf16 on JS
    <<4, x, rest:binary>> -> {
      io.debug("matched")
      use #(label, rest) <- result.then(decode_label(x, rest))
      use #(value, rest) <- result.then(decode(rest))
      use #(then, rest) <- result.then(decode(rest))
      Ok(#(e.Let(label, value, then), rest))
      todo
    }
  }
  //   Ok(#(e.Variable(label), rest))

  // <<4, x, rest:binary>> -> {
  //   io.debug("matched")
  //   use #(label, rest) <- result.then(decode_label(x, rest))
  //   use #(value, rest) <- result.then(decode(rest))
  //   use #(then, rest) <- result.then(decode(rest))
  //   Ok(#(e.Let(label, value, then), rest))
  // }
  // <<5, value:32, rest:binary>> -> Ok(#(e.Integer(value), rest))
  // _ -> {
  //   io.debug(bytes)
  //   todo("some bytes")
  // }
}

pub fn round_trip_test() -> Nil {
  let tree = e.Let("xyz", e.Integer(5), e.Variable("xyz"))
  let source = linear(tree)
  decode(source)
  |> should.equal(Ok(#(tree, <<>>)))

  //   gather_hash(<<1, 1, "ab":utf8>>)
  gather_hash(source)
  todo
}
