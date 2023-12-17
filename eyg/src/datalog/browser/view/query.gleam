import gleam/io
import gleam/dict
import gleam/int
import gleam/list
import gleam/listx
import gleam/string
import lustre/attribute.{class}
import lustre/effect
import lustre/element.{text}
import lustre/element/html.{br, div, span, textarea}
import lustre/event.{on_input}
import datalog/evaluation/naive
import datalog/ast
import datalog/ast/parser
import datalog/browser/app/model.{Model}
import datalog/browser/view/value
import datalog/browser/view/source

pub fn render(i, constraints, r) {
  let constraint_els = list.index_map(constraints, constraint)
  div([class("cover")], [
    span([], [text(int.to_string(i))]),
    br([]),
    div([], constraint_els),
    results(naive.run(ast.Program(constraints))),
    textarea([class("w-full border"), on_input(handle_edit(_, i))]),
    ..case r {
      Ok(Nil) -> []
      Error(parser.TokenError(got)) -> [
        div([class("bg-red-300")], [text("invalid token"), text(got)]),
      ]
      Error(parser.ParseError(expected, got)) -> [
        div([class("bg-red-300")], [
          text("parse error expected: "),
          text(string.join(expected, ", ")),
          text(string.inspect(got)),
        ]),
      ]
    }
  ])
}

fn results(result) {
  case result {
    Ok(tables) -> {
      let tables = dict.to_list(tables)

      div(
        [],
        list.map(tables, fn(t) {
          let #(r, values) = t
          div([], [div([], [text(r)]), source.display(values)])
        }),
      )
    }
    Error(_) -> div([], [text("results")])
  }
}

fn handle_edit(text, index) {
  model.Wrap(fn(model) {
    let Model(sections) = model
    let assert Ok(sections) =
      listx.map_at(sections, index, fn(s) {
        case parser.parse(text) {
          Ok(program) -> {
            let assert model.Query(prog, state) = s
            model.Query(program, Ok(Nil))
          }
          Error(reason) -> {
            let assert model.Query(prog, state) = s
            model.Query(prog, Error(reason))
          }
        }
      })

    let model = Model(sections)
    #(model, effect.none())
  })
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
      ast.Literal(v) -> value.render(v)
    }
  })
  |> list.intersperse(text(", "))
}
