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

pub fn self_join_test() {
  let x = v("x")
  let p =
    ast.Program([
      fact("A", [i(7), i(7)]),
      fact("A", [i(1), i(2)]),
      rule("R", [x], [y("A", [x, x])]),
    ])

  let assert Ok(db) = run(p)

  dict.size(db)
  |> should.equal(2)
  let assert Ok(rows) = dict.get(db, "R")
  rows
  |> should.equal([[ast.I(7)]])
}

pub fn derived_test() {
  let x = v("x")
  let p =
    ast.Program([
      fact("A", [i(3)]),
      rule("B", [x], [y("A", [x])]),
      rule("C", [x], [y("B", [x])]),
    ])

  let assert Ok(db) = run(p)

  dict.size(db)
  |> should.equal(3)
  let assert Ok(rows) = dict.get(db, "B")
  rows
  |> should.equal([[ast.I(3)]])
  let assert Ok(rows) = dict.get(db, "C")
  rows
  |> should.equal([[ast.I(3)]])
}

pub fn recursive_rule_test() {
  let v1 = v("v1")
  let v2 = v("v2")
  let v3 = v("v3")

  let p =
    ast.Program([
      fact("Edge", [i(1), i(2)]),
      fact("Edge", [i(2), i(3)]),
      fact("Edge", [i(3), i(4)]),
      fact("Edge", [i(4), i(4)]),
      rule("Path", [v1, v2], [y("Edge", [v1, v2])]),
      rule("Path", [v1, v3], [y("Edge", [v1, v2]), y("Path", [v2, v3])]),
    ])

  let assert Ok(db) = run(p)

  dict.size(db)
  |> should.equal(2)
  let assert Ok(rows) = dict.get(db, "Path")
  rows
  |> should.equal([
    [ast.I(1), ast.I(4)],
    [ast.I(1), ast.I(3)],
    [ast.I(2), ast.I(4)],
    [ast.I(1), ast.I(2)],
    [ast.I(2), ast.I(3)],
    [ast.I(3), ast.I(4)],
    [ast.I(4), ast.I(4)],
  ])
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
