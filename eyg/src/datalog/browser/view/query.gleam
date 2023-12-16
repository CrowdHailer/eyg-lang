import gleam/int
import gleam/list
import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{br, div, span}
import datalog/ast

pub fn render(i, constraints) {
  let constraints = list.index_map(constraints, constraint)
  div([class("cover")], [
    span([], [text(int.to_string(i))]),
    br([]),
    ..constraints
  ])
}

fn constraint(_index, c) {
  let ast.Constraint(head, body) = c
  case body {
    [] -> fact(head)
    _ -> rule(head, body)
  }
}

fn fact(a) {
  span([], [atom(a), text("."), br([])])
}

fn rule(head, body) {
  span(
    [],
    list.flatten([
      [atom(head), text(" :- ")],
      list.map(body, body_atom)
      |> list.intersperse(span([class("outline")], [text(", ")])),
      [br([])],
    ]),
  )
}

fn body_atom(b) {
  let #(negated, a) = b
  case negated {
    True ->
      span([], [
        span([class("text-blue-500 font-bold")], [text("not ")]),
        atom(a),
      ])
    False -> atom(a)
  }
}

fn atom(a) {
  let ast.Atom(relation, ts) = a

  span(
    [],
    list.flatten([
      // main code all colors are in to_html function and uses neo.css
      [span([class("text-blue-500")], [text(relation)]), text("(")],
      terms(ts),
      [text(")")],
    ]),
  )
}

fn terms(ts) {
  list.map(ts, fn(t) {
    case t {
      ast.Variable(var) -> text(var)
      ast.Literal(value) -> literal(value)
    }
  })
  |> list.intersperse(text(", "))
}

fn literal(value) {
  case value {
    ast.B(True) -> text("true")
    ast.B(False) -> text("false")
    ast.I(i) -> text(int.to_string(i))
    ast.S(s) -> text(s)
  }
}
