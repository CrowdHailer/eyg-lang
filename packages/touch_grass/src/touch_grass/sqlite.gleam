//// Run one SQL statement against a SQLite database file.
////
//// A general effect for creating tables, loading data and reading results.
//// Parameters are always bound, never spliced into the statement.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/list
import gleam/result.{try}

pub const label = "SQLite"

pub type Value {
  Integer(Int)
  Text(String)
  Blob(BitArray)
  Null
}

pub type Input {
  Input(database: String, sql: String, parameters: List(Value))
}

pub fn value() {
  t.union([
    #("Integer", t.Integer),
    #("Text", t.String),
    #("Blob", t.Binary),
    #("Null", t.unit),
  ])
}

pub fn lift() {
  t.record([
    #("database", t.String),
    #("sql", t.String),
    #("parameters", t.List(value())),
  ])
}

pub fn lower() {
  t.result(t.List(t.List(value())), t.String)
}

pub fn decode(input) {
  use database <- try(cast.field("database", cast.as_string, input))
  use sql <- try(cast.field("sql", cast.as_string, input))
  use parameters <- try(cast.field(
    "parameters",
    cast.as_list_of(_, decode_value),
    input,
  ))
  Ok(Input(database:, sql:, parameters:))
}

fn decode_value(value) {
  cast.as_variant(value, [
    #("Integer", cast.map(cast.as_integer, Integer)),
    #("Text", cast.map(cast.as_string, Text)),
    #("Blob", cast.map(cast.as_binary, Blob)),
    #("Null", cast.as_unit(_, Null)),
  ])
}

pub fn encode_value(value) {
  case value {
    Integer(i) -> v.Tagged("Integer", v.Integer(i))
    Text(s) -> v.Tagged("Text", v.String(s))
    Blob(b) -> v.Tagged("Blob", v.Binary(b))
    Null -> v.Tagged("Null", v.unit())
  }
}

pub fn encode(result) {
  case result {
    Ok(rows) ->
      v.ok(
        v.LinkedList(
          list.map(rows, fn(row) { v.LinkedList(list.map(row, encode_value)) }),
        ),
      )
    Error(reason) -> v.error(v.String(reason))
  }
}
