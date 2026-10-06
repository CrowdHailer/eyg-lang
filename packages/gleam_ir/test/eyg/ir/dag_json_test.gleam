import eyg/ir/dag_json as codec
import eyg/ir/helpers
import eyg/ir/integer
import eyg/ir/tree
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

pub fn query_operations_round_trip_test() {
  [
    tree.EmptyTable,
    tree.Fact("Edge"),
    tree.Rule,
    tree.Merge,
    tree.Resolve("Out"),
  ]
  |> list.each(fn(operation) {
    let source = tree.query(operation)
    source
    |> codec.to_string
    |> json.parse(codec.decoder(Nil))
    |> should.equal(Ok(source))
    tree.map_annotation(source, fn(_) { 42 })
    |> tree.clear_annotation()
    |> should.equal(source)
  })
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

    let calculated =
      helpers.cid_from_tree(source)
      |> v1.to_string

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

pub fn reference_round_trip_test() {
  let cid = codec.vacant_cid
  let references = [
    tree.reference(cid),
    tree.package("standard"),
    tree.version("standard", 3),
    tree.release("standard", 3, cid),
    tree.relative("./module.eyg"),
  ]

  references
  |> list.each(fn(reference) {
    reference
    |> codec.to_string
    |> json.parse(codec.decoder(Nil))
    |> should.equal(Ok(reference))
  })
}

pub fn reject_pinned_reference_without_version_test() {
  let source =
    "{\"0\":\"@\",\"p\":\"standard\",\"l\":{\"/\":\""
    <> v1.to_string(codec.vacant_cid)
    <> "\"}}"

  source
  |> json.parse(codec.decoder(Nil))
  |> result.is_error
  |> should.be_true
}

pub fn shallow_encoding_is_distinct_and_round_trips_test() {
  let source = tree.shallow("Ping")
  source |> codec.to_string |> should.equal("{\"0\":\"hs\",\"l\":\"Ping\"}")
  source
  |> codec.to_string
  |> json.parse(codec.decoder(Nil))
  |> should.equal(Ok(source))
  tree.handle("Ping")
  |> codec.to_string
  |> should.equal("{\"0\":\"h\",\"l\":\"Ping\"}")
  tree.map_annotation(source, fn(_) { 42 })
  |> should.equal(#(tree.Shallow("Ping"), 42))
  tree.rewrite_with(source, 0, fn(acc, node) { fn(k) { k(#(acc + 1, node)) } })(
    fn(x) { x },
  )
  |> should.equal(#(1, source))
}

pub fn mask_encoding_and_traversals_test() {
  let source = tree.mask("Ping")
  source |> codec.to_string |> should.equal("{\"0\":\"hm\",\"l\":\"Ping\"}")
  source
  |> codec.to_string
  |> json.parse(codec.decoder(Nil))
  |> should.equal(Ok(source))
  tree.map_annotation(source, fn(_) { 42 })
  |> should.equal(#(tree.Mask("Ping"), 42))
  tree.rewrite_with(source, 0, fn(acc, node) { fn(k) { k(#(acc + 1, node)) } })(
    fn(x) { x },
  )
  |> should.equal(#(1, source))
}
