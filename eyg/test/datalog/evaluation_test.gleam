import gleam/io
import gleam/dict
import datalog/ast
import datalog/evaluation/naive
import datalog/ast/builder.{fact, i, n, rule, v, y}
import gleeunit/should

fn run(program) {
  naive.run(program)
}

pub fn single_fact_test() {
  let p = ast.Program([fact("A", [i(1)]), fact("A", [i(2)])])

  let assert Ok(db) = run(p)

  dict.size(db)
  |> should.equal(1)
  let assert Ok(rows) = dict.get(db, "A")
  rows
  |> should.equal([[ast.I(2)], [ast.I(1)]])
}

pub fn single_match_test() {
  let x = v("x")
  let p = ast.Program([fact("A", [i(1)]), rule("B", [x], [y("A", [x])])])

  let assert Ok(db) = run(p)

  dict.size(db)
  |> should.equal(2)
  let assert Ok(rows) = dict.get(db, "A")
  rows
  |> should.equal([[ast.I(1)]])
  let assert Ok(rows) = dict.get(db, "B")
  rows
  |> should.equal([[ast.I(1)]])
}

pub fn unbound_variable_in_fact_test() {
  let x = v("x")
  let p = ast.Program([fact("A", [x])])

  let assert Error(reason) = run(p)
  should.equal(reason, naive.UnboundVariable("x"))
}

pub fn unbound_variable_in_rule_test() {
  let x = v("x")
  let p = ast.Program([fact("A", [i(1)]), rule("B", [x], [y("A", [i(1)])])])

  let assert Error(reason) = run(p)
  should.equal(reason, naive.UnboundVariable("x"))
}

pub fn single_join_test() {
  let x = v("x")
  let p =
    ast.Program([
      fact("A", [i(1)]),
      fact("B", [i(1)]),
      fact("A", [i(2)]),
      rule("J", [x], [y("A", [x]), y("B", [x])]),
    ])

  let assert Ok(db) = run(p)

  dict.size(db)
  |> should.equal(3)
  let assert Ok(rows) = dict.get(db, "J")
  rows
  |> should.equal([[ast.I(1)]])
}
// pub fn single_negation_test() {
//   let x = v("x")
//   let p =
//     ast.Program([
//       fact("A", [i(1)]),
//       fact("B", [i(1)]),
//       fact("A", [i(2)]),
//       rule("J", [x], [y("A", [x]), n("B", [x])]),
//     ])

//   let assert Ok(db) = run(p)

//   dict.size(db)
//   |> should.equal(3)
//   let assert Ok(rows) = dict.get(db, "J")
//   rows
//   |> should.equal([[ast.I(2)]])
// }

// pub fn single_rule_test() {
//   panic("skipped")
//   let x = v("x")

//   let p =
//     ast.Program([
//       fact("A", [i(1), i(2)]),
//       fact("A", [i(7), i(3)]),
//       fact("A", [i(4), i(4)]),
//       rule("B", [x], [y("A", [x, i(2)])]),
//       rule("C", [x], [y("A", [x, x])]),
//     ])

//   let assert Ok(db) = run(p)

//   dict.size(db)
//   |> should.equal(3)
//   let assert Ok(rows) = dict.get(db, "B")
//   rows
//   |> should.equal([[ast.I(2)], [ast.I(1)]])
// }
