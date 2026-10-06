import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/parser as p
import gleeunit/should

pub fn empty_table_is_not_a_package_test() {
  parser.all_from_string("@{}")
  |> should.be_ok()
  |> ir.clear_annotation()
  |> should.equal(ir.query(ir.EmptyTable))
  parser.all_from_string("@standard")
  |> should.be_ok()
  |> ir.clear_annotation()
  |> should.equal(ir.package("standard"))
}

pub fn query_variables_are_lexically_scoped_test() {
  let source =
    parser.all_from_string(
      "rule Out({x, external}) { var x Input({x}), predicate(x) }",
    )
    |> should.be_ok()
  ir.free_variables(source, []) |> should.equal(["external", "predicate"])
}

pub fn reject_unsafe_and_duplicate_variables_test() {
  parser.all_from_string("rule Out(x) { var x }")
  |> should.be_error()
  |> should.equal(p.InvalidQuery("unbound query variable: x", 5))
  parser.all_from_string("rule Out(1) { var x var x }")
  |> should.be_error()
  |> should.equal(p.InvalidQuery("duplicate query variable: x", 20))
  parser.all_from_string("rule Out(x) { var x !equal(x, 1), Input(x) }")
  |> should.be_error()
  |> should.equal(p.InvalidQuery("unbound query variable: x", 20))
}

pub fn malformed_queries_test() {
  parser.all_from_string("@{") |> should.be_error()
  parser.all_from_string("fact 1") |> should.be_error()
  parser.all_from_string("rule 1 {}") |> should.be_error()
  parser.all_from_string("rule Out(1) {") |> should.be_error()
  parser.all_from_string("resolve out @{}") |> should.be_error()
  parser.all_from_string("rule Out(x) { Input(x) var x }") |> should.be_error()
}

pub fn query_words_remain_valid_binding_and_field_names_test() {
  let assert Ok(_) =
    parser.all_from_string(
      "let resolve = (x) -> { x }
     let fact = 1 let rule = 2 let var = 3
     let record = {resolve, fact, rule, var}
     record.resolve(record.fact)",
    )
}
