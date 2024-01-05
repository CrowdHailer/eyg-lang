import gleam/io
import gleam/dict
import gleam/list
import gleam/listx
import gleam/option.{type Option, None}
import gleam/string
import gleam/uri
import gleam/fetch
import gleam/http/request.{type Request}
import gleam/javascript/promise
import lustre/effect
import datalog/ast
import datalog/ast/parser
import datalog/ast/builder.{fact, i, n, rule, s, v, y}
import datalog/evaluation/naive

pub type Wrap {
  Wrap(fn(Model) -> #(Model, effect.Effect(Wrap)))
}

pub type Model {
  Model(sections: List(Section), mode: Mode)
}

pub type Mode {
  Viewing
  Editing(target: Int, raw: String, parsed: Result(Nil, parser.ParseError))
  SouceSelection(target: Int, raw: String)
  GoogleOAuth(target: Int)
}

pub type Section {
  Query(query: List(ast.Constraint), output: Result(naive.DB, naive.Reason))
  Source(relation: String, table: List(List(ast.Value)))
  RemoteSource(
    request: Request(String),
    relation: String,
    data: List(List(ast.Value)),
  )
  Paragraph(String)
}

pub fn initial() {
  Model(
    run_queries([
      RemoteSource(
        {
          let assert Ok(request) =
            request.from_uri({
              let assert Ok(source) =
                uri.parse("http://localhost:5010/examples/movies.csv")
              source
            })
          request
        },
        "DB",
        [],
      ),
      Query(
        {
          let attr = v("attr")
          let v = v("value")
          [rule("Attr", [attr, v], [y("DB", [s("200"), attr, v])])]
        },
        Ok(dict.new()),
      ),
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
    Viewing,
  )
}

pub fn update_table(state, index, new) {
  let Model(sections, mode) = state
  let assert Ok(sections) =
    listx.map_at(sections, index, fn(s) {
      let assert RemoteSource(req, r, _old) = s
      RemoteSource(req, r, new)
    })
  Model(run_queries(sections), mode)
}

pub fn fetch_source(req) {
  use response <- promise.try_await(fetch.send(req))
  use response <- promise.map_try(fetch.read_text_body(response))

  // gsv doesn't like the something in the valid movies.csv file
  let lines = string.split(response.body, "\n")
  let data = list.map(lines, string.split(_, ","))
  let table = list.map(data, list.map(_, ast.S))
  Ok(table)
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
        RemoteSource(_, relation, table) -> {
          let constraints =
            list.map(table, fn(row) {
              fact(relation, list.map(row, ast.Literal))
            })
          let all = list.append(all, constraints)
          #(all, section)
        }
        Source(relation, table) -> {
          let constraints =
            list.map(table, fn(row) {
              fact(relation, list.map(row, ast.Literal))
            })
          // io.debug(constraints)
          let all = list.append(all, constraints)
          #(all, section)
        }
        s -> #(all, s)
      }
    })
  sections
}
