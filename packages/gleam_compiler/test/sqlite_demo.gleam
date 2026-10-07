//// Run from packages/gleam_compiler: gleam run -m sqlite_demo --runtime bun

import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/compiler/sql
import eyg/parser
import gleam/io
import simplifile

pub fn query() {
  let assert Ok(source) = simplifile.read("../../examples/sqlite/view.eyg")
  let assert Ok(#(expression, [])) = parser.from_string(source)
  sql.to_sql(expression, "Out", [
    sql.Source("Grant", "grants", [
      sql.Column("actor", "actor", t.String),
      sql.Column("resource", "resource", t.String),
      sql.Column("action", "action", t.String),
    ]),
    sql.Source("Child", "children", [
      sql.Column("parent", "parent", t.String),
      sql.Column("child", "child", t.String),
    ]),
  ])
}

pub fn main() {
  let assert Ok(query) = query()
  let target = "../../examples/sqlite/.generated"
  let assert Ok(_) = simplifile.create_directory_all(target)
  let assert Ok(_) = simplifile.write(target <> "/query.mjs", query.javascript)
  let assert Ok(_) =
    simplifile.write(target <> "/query.d.mts", query.typescript)
  io.println("Generated query.mjs and query.d.mts")
  io.println("Inferred Out: " <> debug.mono(query.result_type))
}
