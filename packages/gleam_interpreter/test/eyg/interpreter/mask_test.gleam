import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/value
import eyg/parser
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleeunit/should
import simplifile

pub fn unchecked_masking_and_purity_test() {
  let fixtures =
    simplifile.read("../../spec/masking.json")
    |> should.be_ok
    |> json.parse(
      decode.list({
        use name <- decode.field("name", decode.string)
        use source <- decode.field("source", decode.string)
        use expected <- decode.field("value", decode.int)
        decode.success(#(name, source, expected))
      }),
    )
    |> should.be_ok
  list.each(fixtures, fn(fixture) {
    let #(name, source, expected) = fixture
    let tree = parser.all_from_string(source) |> should.be_ok
    #(name, expression.execute(tree, []))
    |> should.equal(#(name, Ok(value.Integer(expected))))
  })
}

pub fn unchecked_masking_and_purity_errors_test() {
  let fixtures =
    simplifile.read("../../spec/masking_errors.json")
    |> should.be_ok
    |> json.parse(
      decode.list({
        use name <- decode.field("name", decode.string)
        use source <- decode.field("source", decode.string)
        use expected <- decode.field("error", decode.string)
        decode.success(#(name, source, expected))
      }),
    )
    |> should.be_ok
  list.each(fixtures, fn(fixture) {
    let #(name, source, expected) = fixture
    let tree = parser.all_from_string(source) |> should.be_ok
    let assert Error(#(reason, _, _, _)) = expression.execute(tree, [])
    let actual = case reason {
      break.ImpureEffect(_, _) -> "ImpureEffect"
      break.MaskedEffect(_, _) -> "MaskedEffect"
      _ -> "unexpected error"
    }
    #(name, actual) |> should.equal(#(name, expected))
  })
}
