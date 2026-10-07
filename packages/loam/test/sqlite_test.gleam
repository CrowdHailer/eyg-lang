import eyg/compiler/sql
import eyg/interpreter/expression
import eyg/interpreter/simple_debug as debug
import eyg/interpreter/value as v
import eyg/parser
import gleam/dict
import gleam/list
import gleam/string
import loam/sqlite
import loam/system
import simplifile

fn database(name) {
  let path = "build/sqlite_test_" <> name <> ".sqlite"
  let _ = simplifile.delete(path)
  path
}

fn drive(effect) {
  case effect {
    system.Done(value) -> value
    system.Sql(database, statement, params, resume) ->
      drive(resume(system.run_sql(database, statement, params)))
    _ -> panic as "only SQL effects are expected"
  }
}

fn exec(database, statement) {
  let assert Ok(_) = system.run_sql(database, statement, [])
  Nil
}

fn resolve(database, source, relation) {
  let assert Ok(source) = parser.all_from_string(source)
  let assert Ok(v.Table(facts, rules)) = expression.execute(source, [])
  let assert Ok(plan) = sql.plan(facts, rules)
  case drive(sqlite.resolve(database, plan)) {
    Ok(#(facts, _statements)) -> {
      let assert Ok(rows) = list.key_find(facts, relation)
      Ok(rows)
    }
    Error(reason) -> Error(reason)
  }
}

fn temporary_tables(database) {
  let assert Ok(system.SqlResult(rows:, ..)) =
    system.run_sql(database, "SELECT name FROM sqlite_temp_master", [])
  rows
}

fn record(fields) {
  v.Record(dict.from_list(fields))
}

pub fn recursive_rules_reach_a_fixed_point_test() {
  let db = database("recursive")
  exec(db, "CREATE TABLE Edge (\"from\" TEXT, \"to\" TEXT)")
  exec(db, "INSERT INTO Edge VALUES ('A','B'), ('B','C'), ('C','A'), ('A','B')")
  let query =
    "@{
      rule Reach({from, to}) { var from var to Edge({from, to}) }
      rule Reach({from, to}) {
        var from var to var middle
        Reach({from, to: middle}), Reach({from: middle, to})
      }
      rule Out({to}) { var to Reach({from: \"A\", to}) }
    }"
  let assert Ok(rows) = resolve(db, query, "Out")
  assert list.sort(rows, compare)
    == [
      record([#("to", v.String("A"))]),
      record([#("to", v.String("B"))]),
      record([#("to", v.String("C"))]),
    ]
  assert temporary_tables(db) == []
  exec(db, "DELETE FROM Edge")
  assert resolve(db, query, "Out") == Ok([])
}

pub fn mutual_recursion_with_inline_facts_test() {
  let db = database("mutual")
  exec(db, "CREATE TABLE Edge (\"from\" TEXT, \"to\" TEXT)")
  exec(
    db,
    "INSERT INTO Edge VALUES ('A','B'),('B','C'),('C','A'),('B','B'),('D','D')",
  )
  let query =
    "let root = \"A\"
    @{
      fact Seen({node: root}),
      rule Next({node: to}) { var from var to Seen({node: from}), Edge({from, to}) },
      rule Seen({node}) { var node Next({node}) },
      rule Out({node}) { var node Seen({node}), Edge({from: node, to: node}) }
    }"
  assert resolve(db, query, "Out") == Ok([record([#("node", v.String("B"))])])
}

pub fn captured_helpers_and_guards_run_in_sql_test() {
  let db = database("helpers")
  exec(db, "CREATE TABLE Movie (title TEXT, year INTEGER)")
  exec(
    db,
    "INSERT INTO Movie VALUES ('Alien', 1979), ('Predator', 1987), ('RoboCop', 1987)",
  )
  let query =
    "let after = (year, limit) -> {
      match !int_compare(year, limit) { Gt(_) -> { True({}) } | (_) -> { False({}) } }
    }
    let label = (title) -> { !string_append(\"film: \", title) }
    @{ rule Out({label: label(title), next: !int_add(year, 1)}) {
      var title var year
      Movie({title, year}),
      after(year, 1980)
    } }"
  let assert Ok(rows) = resolve(db, query, "Out")
  assert list.sort(rows, compare)
    == [
      record([
        #("label", v.String("film: Predator")),
        #("next", v.Integer(1988)),
      ]),
      record([
        #("label", v.String("film: RoboCop")),
        #("next", v.Integer(1988)),
      ]),
    ]
}

pub fn values_are_parameters_not_sql_test() {
  let db = database("injection")
  exec(db, "CREATE TABLE Host (n INTEGER)")
  exec(db, "CREATE TABLE \"Ta\"\"ble\" (\"co\"\"l\" TEXT)")
  let query =
    "@{
      fact Input({text: \"x'); DROP TABLE Host; --\"}),
      rule Out({text}) { var text Input({text}) }
    }"
  assert resolve(db, query, "Out")
    == Ok([record([#("text", v.String("x'); DROP TABLE Host; --"))])])
  let assert Ok(_) = system.run_sql(db, "SELECT count(*) FROM Host", [])
}

pub fn missing_tables_are_reported_test() {
  let db = database("missing")
  let assert Error(_) =
    resolve(db, "@{ rule Out({n}) { var n Input({n}) } }", "Out")
  assert temporary_tables(db) == []
}

fn compare(a, b) {
  string.compare(debug.inspect(a), debug.inspect(b))
}
