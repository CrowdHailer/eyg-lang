import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/parser
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleeunit/should
import simplifile

fn check(source) {
  let tree = parser.all_from_string(source) |> should.be_ok
  let assert j.Done(analysis) = j.check(j.pure(), tree)
  analysis
}

pub fn shared_shallow_semantics_typecheck_test() {
  let decoder =
    decode.list({
      use name <- decode.field("name", decode.string)
      use source <- decode.field("source", decode.string)
      decode.success(#(name, source))
    })
  let fixtures =
    simplifile.read("../../spec/shallow_handlers.json")
    |> should.be_ok
    |> json.parse(decoder)
    |> should.be_ok
  list.each(fixtures, fn(fixture) {
    let #(name, source) = fixture
    let analysis = check(source)
    #(name, j.all_errors(analysis)) |> should.equal(#(name, []))
    j.type_(analysis) |> should.equal(t.Integer)
  })
}

pub fn rejects_unhandled_resumption_and_mismatched_types_test() {
  let programs = [
    // A raw continuation still requires Ping, even if the body performs it once.
    "let k = handle shallow Ping((_, k) -> { k }, (x) -> { (_) -> { x } },
      (_) -> { perform Ping({}) }) k(1)",
    // Residual effects before the first handled operation must not disappear.
    "handle shallow Ping((_, _) -> { 1 }, (x) -> { x },
      (_) -> { let _ = perform Other({}) perform Ping({}) })",
    // The callback and return clause must agree on their answer type.
    "handle shallow Ping((_, _) -> { 1 }, (_) -> { \"wrong\" }, (_) -> { 0 })",
    // A resumed reply remains tied to the use inside the original body.
    "let k = handle shallow Ping((_, k) -> { k }, (x) -> { (_) -> { x } },
      (_) -> { !int_add(perform Ping({}), 1) })
      handle Ping((_, _) -> { 0 }, (_) -> { k(\"wrong\") })",
    // Return-clause effects are outside the delimiter too.
    "handle shallow Ping((_, _) -> { 0 }, (_) -> { perform Ping({}) }, (_) -> { 1 })",
  ]
  list.each(programs, fn(source) {
    check(source) |> j.all_errors |> list.is_empty |> should.be_false
  })
}

pub fn direct_shallow_forwarding_hits_the_scoped_row_limit_test() {
  // Known conservative restriction, not a runtime failure: requiring the same
  // row both with and without Ping makes epsilon = <Ping | epsilon>.
  let analysis =
    check(
      "handle Ping((_, k) -> { k(100) }, (_) -> {
      handle shallow Ping((_, k) -> { k(1) }, (x) -> { x }, (_) -> {
        let a = perform Ping({}) let b = perform Ping({}) !int_add(a, b)
      })
    })",
    )
  j.all_errors(analysis)
  |> list.map(fn(pair) { pair.1 })
  |> list.contains(error.Recursive)
  |> should.be_true
}
