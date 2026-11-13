import cloud/database
import eyg/compiler/sql
import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/parser
import gleam/dict
import gleam/list
import simplifile
import touch_grass/sqlite

fn fresh(name) {
  let assert Ok(path) = database.path("build/database_test", name)
  let _ = simplifile.delete(path)
  path
}

pub fn names_cannot_leave_the_data_directory_test() {
  assert database.path("/data", "errors") == Ok("/data/databases/errors.sqlite")
  let assert Error(_) = database.path("/data", "../secrets")
  let assert Error(_) = database.path("/data", "a/b")
  let assert Error(_) = database.path("/data", "")
}

pub fn statements_bind_parameters_test() {
  let db = fresh("statements")
  let assert Ok([]) =
    database.run(
      db,
      "CREATE TABLE notes (author TEXT, body TEXT, n INTEGER)",
      [],
    )
  let assert Ok([]) =
    database.run(db, "INSERT INTO notes VALUES (?, ?, ?), (?, ?, ?)", [
      sqlite.Text("alice"),
      sqlite.Text("'; DROP TABLE notes; --"),
      sqlite.Integer(1),
      sqlite.Text("bob"),
      sqlite.Null,
      sqlite.Integer(2),
    ])
  assert database.run(db, "SELECT body, n FROM notes ORDER BY n", [])
    == Ok([
      [sqlite.Text("'; DROP TABLE notes; --"), sqlite.Integer(1)],
      [sqlite.Null, sqlite.Integer(2)],
    ])
  let assert Error(_) = database.run(db, "SELECT * FROM missing", [])
}

fn record(fields) {
  v.Record(dict.from_list(fields))
}

pub fn query_tables_resolve_in_the_database_test() {
  let db = fresh("query")
  let assert Ok(_) =
    database.run(db, "CREATE TABLE Edge (\"from\" TEXT, \"to\" TEXT)", [])
  let assert Ok(_) =
    database.run(
      db,
      "INSERT INTO Edge VALUES ('A','B'), ('B','C'), ('C','A')",
      [],
    )
  let source =
    "@{
      rule Reach({from, to}) { var from var to Edge({from, to}) }
      rule Reach({from, to}) {
        var from var to var middle
        Reach({from, to: middle}), Reach({from: middle, to})
      }
      rule Out({to}) { var to Reach({from: \"A\", to}) }
    }"
  let assert Ok(source) = parser.all_from_string(source)
  let assert Ok(v.Table(facts, rules)) = expression.execute(source, [])
  let assert Ok(plan) = sql.plan(facts, rules)
  let assert Ok(#(facts, statements)) = database.resolve(db, plan)
  let assert Ok(rows) = list.key_find(facts, "Out")
  assert list.length(rows) == 3
  assert list.contains(rows, record([#("to", v.String("C"))]))
  assert statements != []
  // Temporary tables are dropped.
  assert database.run(db, "SELECT name FROM sqlite_temp_master", []) == Ok([])
}

pub fn recursive_empty_records_reach_a_fixed_point_test() {
  let db = fresh("empty_records")
  let assert Ok(source) =
    parser.all_from_string(
      "@{ fact Ready({}), rule Ready({}) { var row Ready(row) } }",
    )
  let assert Ok(v.Table(facts, rules)) = expression.execute(source, [])
  let assert Ok(plan) = sql.plan(facts, rules)
  let assert Ok(#(facts, _)) = database.resolve(db, plan)
  assert list.key_find(facts, "Ready") == Ok([v.unit()])
}
