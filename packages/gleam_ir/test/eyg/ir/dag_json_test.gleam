import dag_json
import eyg/ir/cid
import eyg/ir/dag_json as codec
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/io
import gleam/list
import gleeunit/should
import simplifile

type Fixture {
  Fixture(name: String, source: Dynamic, cid: String)
}

fn fixture_decoder() {
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

pub fn dag_json_test() {
  let fixtures =
    simplifile.read_bits("../../ir/ir_fixtures.json")
    |> should.be_ok
    |> dag_json.decode()
    |> should.be_ok
    |> decode.run(fixture_decoder())
    |> should.be_ok

  list.map(fixtures, fn(fixture) {
    let Fixture(name, raw, cid) = fixture
    let source =
      codec.decode(raw)
      |> should.be_ok
    case cid.from_tree(source) == cid {
      True -> Nil
      False -> {
        cid.from_tree(source) |> io.debug
        panic as { "test failed for " <> name }
      }
    }
  })
}
