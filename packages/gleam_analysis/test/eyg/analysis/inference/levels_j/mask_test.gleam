import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/isomorphic as t
import eyg/parser
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleeunit/should
import simplifile

fn fixtures(path) {
  simplifile.read(path)
  |> should.be_ok
  |> json.parse(
    decode.list({
      use name <- decode.field("name", decode.string)
      use source <- decode.field("source", decode.string)
      decode.success(#(name, source))
    }),
  )
  |> should.be_ok
}

pub fn masking_and_purity_types_test() {
  list.each(fixtures("../../spec/masking.json"), fn(fixture) {
    let #(name, source) = fixture
    let tree = parser.all_from_string(source) |> should.be_ok
    let assert j.Done(analysis) = j.check(j.pure(), tree)
    #(name, j.all_errors(analysis)) |> should.equal(#(name, []))
    j.type_(analysis) |> should.equal(t.Integer)
  })
}

pub fn masking_and_purity_reject_invalid_effects_test() {
  list.each(fixtures("../../spec/masking_errors.json"), fn(fixture) {
    let #(_, source) = fixture
    let tree = parser.all_from_string(source) |> should.be_ok
    let assert j.Done(analysis) = j.check(j.pure(), tree)
    j.all_errors(analysis) |> list.is_empty |> should.be_false
  })
}
