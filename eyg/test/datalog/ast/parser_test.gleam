import datalog/ast/builder.{b, fact, i, n, rule, s, v, y}
import datalog/ast/parser.{parse}
import gleeunit/should

pub fn empty_program_test() {
  parse("")
  |> should.equal(Ok([]))
}

pub fn empty_fact_test() {
  parse("empty().")
  |> should.equal(Ok([fact("empty", [])]))
}

pub fn fact_number_test() {
  parse("foo(55).")
  |> should.equal(Ok([fact("foo", [i(55)])]))
}

pub fn fact_string_test() {
  parse("foo(\"a:-,\\\\!\").")
  |> should.equal(Ok([fact("foo", [s("a:-,\\!")])]))
}

pub fn fact_boolean_test() {
  parse("foo(true, false).")
  |> should.equal(Ok([fact("foo", [b(True), b(False)])]))
}

pub fn rules_test() {
  parse("x(a,b) :- y(1, a), z(2, b).")
  |> should.equal(
    Ok([
      rule("x", [v("a"), v("b")], [
        y("y", [i(1), v("a")]),
        y("z", [i(2), v("b")]),
      ]),
    ]),
  )
}

pub fn negated_test() {
  parse("x() :- y(), not z().")
  |> should.equal(Ok([rule("x", [], [y("y", []), n("z", [])])]))
}
