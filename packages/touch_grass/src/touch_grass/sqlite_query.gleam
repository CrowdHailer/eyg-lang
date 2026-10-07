//// Resolve a query table inside a SQLite database.
////
//// Rules become SQL joins run by the database until no new facts appear.
//// Relations the rules do not derive are read from tables of the same name.
//// Returns the derived facts, to `resolve`, and the SQL that was run.
//// Every perform shares one row type: a program has one view of its databases.

import eyg/analysis/type_/isomorphic as t
import eyg/compiler/sql
import eyg/interpreter/cast
import eyg/interpreter/table
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/result.{try}

pub const label = "SQLiteQuery"

pub type Input {
  Input(database: String, plan: Result(sql.Plan, String))
}

fn relations() {
  t.Var(-1)
}

pub fn lift() {
  t.record([#("database", t.String), #("query", t.Table(relations()))])
}

pub fn lower() {
  t.result(
    t.record([#("facts", t.Table(relations())), #("sql", t.List(t.String))]),
    t.String,
  )
}

pub fn decode(input) {
  use database <- try(cast.field("database", cast.as_string, input))
  use #(facts, rules) <- try(cast.field("query", cast.as_table, input))
  Ok(Input(database:, plan: sql.plan(facts, rules)))
}

pub fn encode(result) {
  case result {
    Ok(#(facts, statements)) -> {
      let facts = v.Table(table.from_list(facts), [])
      let statements = v.LinkedList(list.map(statements, v.String))
      v.ok(v.Record(dict.from_list([#("facts", facts), #("sql", statements)])))
    }
    Error(reason) -> v.error(v.String(reason))
  }
}
