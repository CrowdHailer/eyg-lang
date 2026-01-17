import eyg/ir/cid
import eyg/ir/dag_json as codec
import gleam/crypto
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
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
      codec.decode(raw)
      |> should.be_ok
    let cid.Sha256(bytes, resume) = cid.from_tree(source)
    let hash = crypto.hash(crypto.Sha256, bytes)
    let assert Ok(calculated) = resume(hash) |> v1.to_string

    case calculated == expected {
      True -> Nil
      False -> {
        io.println(calculated)
        panic as { "test failed for " <> name }
      }
    }
  })
}
