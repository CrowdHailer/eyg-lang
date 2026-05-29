import eyg/ir/cid
import eyg/ir/dag_json as codec
import eyg/ir/integer
import gleam/crypto
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleeunit/should
import multiformats/cid/v1
import simplifile

type Fixture {
  Fixture(name: String, source: Dynamic, cid: String)
}

fn suite_decoder() {
  decode.list({
    use name <- decode.field("name", decode.string)

    use source <- decode.field(
      "source",
      decode.new_primitive_decoder("raw", Ok),
    )
    use cid <- decode.field("cid", decode.string)
    decode.success(Fixture(name, source, cid))
  })
}

pub fn ir_suite_test() {
  let tests =
    simplifile.read_bits("../../spec/ir_suite.json")
    |> should.be_ok
    |> json.parse_bits(suite_decoder())
    |> should.be_ok

  list.map(tests, fn(fixture) {
    let Fixture(name, raw, expected) = fixture
    let source =
      decode.run(raw, codec.decoder(Nil))
      |> should.be_ok
    let cid.Sha256(bytes, resume) = cid.from_tree(source)
    let hash = crypto.hash(crypto.Sha256, bytes)
    let calculated = resume(hash) |> v1.to_string

    case calculated == expected {
      True -> Nil
      False -> {
        io.println(calculated)
        panic as { "test failed for " <> name }
      }
    }
  })
}

// Decoding an integer succeeds exactly when the target can represent it. On
// JavaScript the native JSON parser rounds a value outside the safe range, so
// it is rejected; on Erlang the same input is an exact bignum and decodes
// fine. Asserting against `integer.is_safe` keeps the test correct on both
// targets (it can't be a shared spec fixture for that reason).
pub fn decode_out_of_safe_range_integer_test() {
  json.parse("{\"0\":\"i\",\"v\":999999999999999000000}", codec.decoder(Nil))
  |> result.is_ok
  |> should.equal(integer.is_safe(999_999_999_999_999 * 1_000_000))
}

pub fn decode_in_range_integer_test() {
  json.parse("{\"0\":\"i\",\"v\":5}", codec.decoder(Nil))
  |> should.be_ok
}
