import eyg/ir/cid
import eyg/ir/dag_json as codec
import eyg/ir/tree as ir
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/io
import gleam/json as j
import gleam/list
import gleeunit/should
import simplifile

type Fixture {
  Fixture(name: String, source: Dynamic)
}

fn fixture_decoder() {
  decode.list({
    use source <- decode.field(
      "source",
      decode.new_primitive_decoder("raw", Ok),
    )
    use name <- decode.field("name", decode.string)
    decode.success(Fixture(name, source))
  })
}

pub fn dag_json_test() {
  let fixtures =
    simplifile.read("../../ir/ir_fixtures.json")
    |> should.be_ok
    |> j.parse(fixture_decoder())
    |> should.be_ok

  // io.debug(fixtures)
  list.map(fixtures, fn(fixture) {
    let Fixture(name, raw) = fixture
    let source =
      codec.decode(raw)
      |> should.be_ok
    io.debug(cid.from_tree(source))
    // encode(source)
    // |> dynamic.from
    // |> should.equal(raw)
    // panic
  })
  // todo
}
