import gleam/dict
import datalog/ast
import datalog/evaluation/naive
import datalog/ast/builder.{fact, i, rule, v, y}
import gleeunit/should

fn run(program) {
  naive.run(program)
}

pub fn single_fact_test() {
  let p =
    ast.Program([
      ast.Constraint(ast.Atom("A", [i(1)]), []),
      ast.Constraint(ast.Atom("A", [i(2)]), []),
    ])

  let db = run(p)

  dict.size(db)
  |> should.equal(1)
  let assert Ok(rows) = dict.get(db, "A")
  rows
  |> should.equal([[ast.I(2)], [ast.I(1)]])
}

pub fn single_rule_test() {
  let x = v("x")

  let p =
    ast.Program([
      fact("A", [i(1), i(2)]),
      fact("A", [i(7), i(3)]),
      fact("A", [i(4), i(4)]),
      rule("B", [x], [y("A", [x, i(2)])]),
      rule("C", [x], [y("A", [x, x])]),
    ])

  let db = run(p)

  dict.size(db)
  |> should.equal(3)
  let assert Ok(rows) = dict.get(db, "B")
  rows
  |> should.equal([[ast.I(2)], [ast.I(1)]])
}
