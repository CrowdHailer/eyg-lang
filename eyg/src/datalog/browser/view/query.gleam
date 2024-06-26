import datalog/ast
import datalog/ast/parser
import datalog/browser/app/model.{Model, Wrap}
import datalog/browser/view/source
import datalog/browser/view/value
import datalog/evaluation/naive
import gleam/dict
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute.{class, value}
import lustre/effect
import lustre/element.{text}
import lustre/element/html.{br, div, span, textarea}
import lustre/event.{on_blur, on_click, on_input}

fn edit_query(index) {
  Wrap(fn(model) {
    let assert Ok(model.Query(constraints, _)) = listx.at(model.sections, index)
    let content = list.map(constraints, constraint_text)
    let content =
      list.intersperse(content, "\r")
      |> string.concat

    let model = Model(..model, mode: model.Editing(index, content, Ok(Nil)))
    #(model, effect.none())
  })
}

fn commit_changes() {
  Wrap(fn(model) {
    let assert Model(sections, model.Editing(id, text, state)) = model
    case state {
      Ok(_) -> {
        let assert Ok(sections) =
          listx.map_at(sections, id, fn(_section) {
            let assert Ok(constraints) = parser.parse(text)
            model.Query(constraints, Ok(dict.new()))
          })
        #(Model(model.run_queries(sections), model.Viewing), effect.none())
      }
      Error(_) -> #(model, effect.none())
    }
  })
}

pub fn render(i, constraints, r, output) {
  let constraint_els = list.index_map(constraints, constraint)
  div(
    [
      class(
        "vstack left wrap left bg-white border-2 border-black rounded w-full neo-shadow",
      ),
    ],
    [
      div([class("hstack tight")], [
        div([class("bg-black text-white font-bold")], [text("Query")]),
        div([class("expand cover bg-orange-2")], []),
      ]),
      ..case r {
        None -> [
          div(
            [class("w-full cursor-pointer"), on_click(edit_query(i))],
            constraint_els,
          ),
          results(output, constraints),
        ]
        Some(#(content, r)) -> {
          let lines =
            string.split(content, ".")
            |> list.length
          // already one extra section than number or newlines. there was an issue with \r
          let rows = int.to_string(lines)
          [
            div([class("p-2 bg-yellow-100 shadow cursor-pointer")], [
              textarea(
                [
                  class("w-full bg-transparent p-2"),
                  attribute.attribute("rows", rows),
                  attribute.attribute("autofocus", "true"),
                  // attribute.autofocus(True),
                  on_input(handle_edit(_)),
                  on_blur(commit_changes()),
                ],
                content,
              ),
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
            ]),
          ]
        }
      }
    ],
  )
}

fn results(result, constraints) {
  case result {
    Ok(tables) -> {
      let relations = ast.relations(constraints)
      let tables = dict.to_list(dict.take(tables, relations))

      // TODO get headings of names in relation
      div(
        [],
        list.map(tables, fn(t) {
          let #(r, values) = t
          div([], [div([], [text(r)]), source.display([], values)])
        }),
      )
    }
    Error(naive.UnboundVariable(var)) ->
      div([class("bg-red-200 shadow py-2 px-4")], [
        text(
          string.concat([
            "failed to answer query because of unbound variable: ",
            var,
          ]),
        ),
      ])
  }
}

fn handle_edit(text) {
  model.Wrap(fn(model) {
    let assert Model(mode: model.Editing(i, _, _), ..) = model
    let state = case parser.parse(text) {
      Ok(program) -> {
        Ok(Nil)
      }
      Error(reason) -> Error(reason)
    }

    let model = Model(..model, mode: model.Editing(i, text, state))
    #(model, effect.none())
  })
}

fn constraint_text(c) {
  let ast.Constraint(head, body) = c
  case body {
    [] -> string.append(atom_text(head), ".")
    _ -> string.concat([atom_text(head), " :- ", body_text(body), "."])
  }
}

fn body_text(body) {
  list.map(body, fn(b_atom) {
    let #(negated, atom) = b_atom
    let prefix = case negated {
      True -> "not "
      False -> ""
    }
    string.append(prefix, atom_text(atom))
  })
  |> list.intersperse(", ")
  |> string.concat
}

fn atom_text(atom) {
  let ast.Atom(r, terms) = atom
  let terms =
    list.map(terms, term_text)
    |> list.intersperse(", ")
    |> string.concat
  string.concat([r, "(", terms, ")"])
}

fn term_text(term) {
  case term {
    ast.Variable(var) -> var
    ast.Literal(ast.B(True)) -> "true"
    ast.Literal(ast.B(False)) -> "false"
    ast.Literal(ast.I(value)) -> int.to_string(value)
    ast.Literal(ast.S(value)) -> string.concat(["\"", value, "\""])
  }
}

fn constraint(c, _index) {
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
