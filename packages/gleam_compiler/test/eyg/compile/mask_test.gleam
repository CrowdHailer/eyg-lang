import eyg/compiler
import eyg/parser
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleeunit/should
import plinth/browser/window
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
    let result =
      compiler.to_js(
        tree,
        dict.new(),
        "() => { throw Error('host effect escaped'); }",
      )
      |> window.eval
    #(name, result) |> should.equal(#(name, Ok(dynamic.int(expected))))
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
    let js =
      compiler.to_js(
        tree,
        dict.new(),
        "() => { throw Error('host effect escaped'); }",
      )
    let wrapped =
      "(() => { try { "
      <> js
      <> "; return 'no error'; } catch (e) { return Object.keys(e.eygBreak || {})[0] || 'host effect escaped'; } })()"
    #(name, window.eval(wrapped))
    |> should.equal(#(name, Ok(dynamic.string(expected))))
  })
}
