import gleam/dict
import gleam/list
import gleam/option.{type Option, None}
import gleam/string
import lustre/effect
import datalog/ast
import datalog/ast/parser
import datalog/ast/builder.{fact, i, n, rule, v, y}
import datalog/evaluation/naive

pub type Wrap {
  Wrap(fn(Model) -> #(Model, effect.Effect(Wrap)))
}

pub type Model {
  Model(
    sections: List(Section),
    editing: Option(#(Int, String, Result(Nil, parser.ParseError))),
  )
}

pub type Section {
  Query(query: List(ast.Constraint), output: Result(naive.DB, naive.Reason))
  Source(relation: String, table: List(List(ast.Value)))
  Paragraph(String)
}

pub fn initial() {
  Model(
    run_queries([
      Query(
        [
          fact("Edge", [i(1), i(2)]),
          fact("Edge", [i(2), i(3)]),
          fact("Edge", [i(3), i(4)]),
          fact("Edge", [i(7), i(3)]),
        ],
        Ok(dict.new()),
      ),
      {
        let x1 = v("x")
        let x2 = v("y")
        let x3 = v("z")
        Query(
          [
            rule("Path", [x1, x2], [y("Edge", [x1, x2])]),
            rule("Path", [x1, x3], [y("Edge", [x1, x2]), y("Path", [x2, x3])]),
          ],
          Ok(dict.new()),
        )
      },
      {
        let x1 = v("x")
        Query(
          [rule("Foo", [x1], [y("Edge", [x1, i(2)]), n("Path", [x1, x1])])],
          Ok(dict.new()),
        )
      },
    ]),
    None,
  )
}

pub fn run_queries(sections) {
  let #(_, sections) =
    list.map_fold(sections, [], fn(all, section) {
      case section {
        Query(constraints, _) -> {
          let #(all, r) = {
            let a = list.append(all, constraints)
            // Don't add constraints if fails
            case naive.run(ast.Program(a)) {
              Ok(r) -> #(a, Ok(r))
              Error(reason) -> #(all, Error(reason))
            }
          }
          #(all, Query(constraints, r))
        }
        s -> #(all, s)
      }
    })
  sections
}
