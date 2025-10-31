import dag_json
import eyg/ir/cid
import eyg/ir/dag_json as codec
import eyg/ir/promise
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise as ogpromise
import gleam/json
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
    |> json.parse_bits(suite_decoder())
    |> should.be_ok

  list.map(tests, fn(fixture) {
    let Fixture(name, raw, expected) = fixture
    let source =
      codec.decode(raw)
      |> should.be_ok
    let assert Ok(calculated) = cid.from_tree(source)
    case calculated == expected {
      True -> Nil
      False -> {
        io.println(calculated)
        panic as { "test failed for " <> name }
      }
    }
  })
}

pub fn ir_async_suite_test() -> ogpromise.Promise(List(Nil)) {
  let tests =
    simplifile.read_bits("../../spec/ir_suite.json")
    |> should.be_ok
    |> json.parse_bits(suite_decoder())
    |> should.be_ok

  list.map(tests, fn(fixture) {
    let Fixture(name, raw, expected) = fixture
    let source =
      codec.decode(raw)
      |> should.be_ok
    use calculated <- promise.map(cid.from_tree_async(source))
    let assert Ok(calculated) = calculated
    case calculated == expected {
      True -> Nil
      False -> {
        io.println(calculated)
        panic as { "test failed for " <> name }
      }
    }
  })
  |> promise.await_list
}
