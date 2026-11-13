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

pub fn shared_shallow_semantics_test() {
  let decoder =
    decode.list({
      use name <- decode.field("name", decode.string)
      use source <- decode.field("source", decode.string)
      use expected <- decode.field("value", decode.int)
      decode.success(#(name, source, expected))
    })
  let fixtures =
    simplifile.read("../../spec/shallow_handlers.json")
    |> should.be_ok
    |> json.parse(decoder)
    |> should.be_ok
  list.each(fixtures, fn(fixture) {
    let #(name, source, expected) = fixture
    let tree = parser.all_from_string(source) |> should.be_ok
    let result =
      compiler.to_js(tree, dict.new(), "(label, _) => { throw Error(label); }")
      |> window.eval
    #(name, result) |> should.equal(#(name, Ok(dynamic.int(expected))))
  })
}

pub fn shallow_does_not_reinstall_itself_test() {
  let tree =
    parser.all_from_string(
      "handle shallow Ping((_, resume) -> { resume({}) }, (x) -> { x }, (_) -> {
      let _ = perform Ping({}) perform Ping({})
    })",
    )
    |> should.be_ok
  // The platform sees the second operation, rather than the shallow callback.
  compiler.to_js(tree, dict.new(), "(label, _) => label === 'Ping' ? 42 : -1")
  |> window.eval
  |> should.equal(Ok(dynamic.int(42)))
}
