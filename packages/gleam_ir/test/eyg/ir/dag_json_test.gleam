import dag_json
import eyg/ir/cid
import eyg/ir/dag_json as codec
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleeunit/should
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
    |> dag_json.decode()
    |> should.be_ok
    |> decode.run(suite_decoder())
    |> should.be_ok

  list.map(tests, fn(fixture) {
    let Fixture(name, raw, expected) = fixture
    let source =
      codec.decode(raw)
      |> should.be_ok
    use calculated <- promise.map(cid.from_tree(source))
    case calculated == expected {
      True -> Nil
      False -> {
        cid.from_tree(source) |> io.debug
        panic as { "test failed for " <> name }
      }
    }
  })
  |> promise.await_list
}
