import datalog/ast
import gleam/list

pub fn fact(relation, values) {
  let terms = list.map(values, fn(v) { v })
  ast.Constraint(ast.Atom(relation, terms), [])
}

pub fn rule(relation, terms, body) {
  ast.Constraint(ast.Atom(relation, terms), body)
}

pub fn v(label) {
  ast.Variable(label)
}

pub fn b(value) {
  ast.Literal(ast.B(value))
}

pub fn i(value) {
  ast.Literal(ast.I(value))
}

pub fn s(value) {
  ast.Literal(ast.S(value))
}

// yes
pub fn y(relation, terms) {
  #(False, ast.Atom(relation, terms))
}

// no
pub fn n(relation, terms) {
  #(True, ast.Atom(relation, terms))
}
