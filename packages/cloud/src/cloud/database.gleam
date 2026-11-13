//// A workspace's SQLite databases, files in its data directory.
////
//// Programs use them with the `SQLite` and `SQLiteQuery` effects, the same effects Loam provides,
//// see `touch_grass/sqlite` and `touch_grass/sqlite_query`.
//// A database is named, `errors` is `<data>/databases/errors.sqlite`, so programs never see paths.
//// Raw database access is for trusted channels, other channels use dataclips, see `cloud/dataclip`.

import eyg/compiler/sql
import eyg/interpreter/value as v
import filepath
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import simplifile
import sqlight
import touch_grass/sqlite

/// The file of a named database in a workspace's data directory.
/// Names are letters, digits, `_` and `-`, so a name cannot leave the directory.
pub fn path(data_directory: String, name: String) -> Result(String, String) {
  let valid =
    name != ""
    && string.to_graphemes(name)
    |> list.all(fn(c) { string.contains(allowed, c) })
  case valid {
    True -> Ok(filepath.join(data_directory, "databases/" <> name <> ".sqlite"))
    False ->
      Error(
        "database names are letters, digits, _ and -, not "
        <> string.inspect(name),
      )
  }
}

const allowed =
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"

fn with_connection(
  path: String,
  run: fn(sqlight.Connection) -> Result(a, String),
) {
  let _ = simplifile.create_directory_all(filepath.directory_name(path))
  use connection <- result.try(sqlight.open(path) |> result.map_error(describe))
  let result = run(connection)
  let _ = sqlight.close(connection)
  result
}

/// Run one statement with bound parameters, returning its rows.
pub fn run(
  path: String,
  statement: String,
  parameters: List(sqlite.Value),
) -> Result(List(List(sqlite.Value)), String) {
  use connection <- with_connection(path)
  query(connection, statement, list.map(parameters, parameter))
}

fn query(connection, statement, parameters) {
  sqlight.query(statement, on: connection, with: parameters, expecting: row())
  |> result.map_error(describe)
}

fn parameter(value: sqlite.Value) -> sqlight.Value {
  case value {
    sqlite.Integer(i) -> sqlight.int(i)
    sqlite.Text(text) -> sqlight.text(text)
    sqlite.Blob(bytes) -> sqlight.blob(bytes)
    sqlite.Null -> sqlight.null()
  }
}

/// Every column of a row, whatever its type.
fn row() -> decode.Decoder(List(sqlite.Value)) {
  use values <- decode.then(decode.dynamic)
  decode.success(list.map(tuple_values(values), column))
}

/// SQLite has no booleans, and floats are returned as text.
fn column(value: Dynamic) -> sqlite.Value {
  let decoder =
    decode.one_of(decode.int |> decode.map(sqlite.Integer), [
      decode.float
        |> decode.map(fn(f) { sqlite.Text(float.to_string(f)) }),
      decode.string |> decode.map(sqlite.Text),
      decode.bit_array |> decode.map(sqlite.Blob),
    ])
  decode.run(value, decoder) |> result.unwrap(sqlite.Null)
}

fn describe(error: sqlight.Error) -> String {
  error.message
}

@external(erlang, "cloud_ffi", "tuple_values")
fn tuple_values(row: Dynamic) -> List(Dynamic)

/// Resolve a planned query table, returning the derived facts and the statements that were run.
/// Rules are repeated until a round adds no facts, a rule only runs again when a relation it reads grew.
/// This is Loam's resolution, run with one connection so temporary tables last for the query.
pub fn resolve(
  path: String,
  plan: sql.Plan,
) -> Result(#(List(#(String, List(v.Value(m, c)))), List(String)), String) {
  use connection <- with_connection(path)
  let sql.Plan(relations:, seeds:, rules:) = plan
  let tables = "SELECT name FROM main.sqlite_master WHERE type = 'table'"
  use existing <- result.try(query(connection, tables, []))
  let existing = list.flatten(existing)
  let drop = list.map(relations, sql.drop)
  use log <- result.try(statements(connection, drop, []))
  let create =
    list.flat_map(relations, fn(relation) {
      case list.contains(existing, sqlite.Text(relation.label)) {
        True -> [sql.create(relation), sql.seed_from_main(relation)]
        False -> [sql.create(relation)]
      }
    })
  let outcome = {
    use log <- result.try(statements(connection, create, log))
    use log <- result.try(
      list.try_fold(seeds, log, fn(log, seed) {
        let sql.Statement(text, params) = seed
        use _ <- result.map(execute(connection, text, params))
        [text, ..log]
      }),
    )
    let log =
      list.fold(rules, log, fn(log, rule) { [rule.statement.sql, ..log] })
    use Nil <- result.try(rounds(connection, rules, rules, 1000))
    use facts <- result.map(list.try_map(relations, read(connection, _)))
    #(facts, list.reverse(log))
  }
  let _ = statements(connection, drop, [])
  outcome
}

fn statements(connection, statements, log) {
  list.try_fold(statements, log, fn(log, statement) {
    use _ <- result.map(execute(connection, statement, []))
    [statement, ..log]
  })
}

fn execute(connection, text, params) {
  query(connection, text, list.map(params, sql_parameter))
  |> result.map_error(fn(reason) { reason <> " in " <> text })
}

fn sql_parameter(param) {
  case param {
    sql.Integer(i) -> sqlight.int(i)
    sql.Text(s) -> sqlight.text(s)
    sql.Blob(b) -> sqlight.blob(b)
  }
}

fn rounds(connection, all: List(sql.Rule), pending: List(sql.Rule), remaining) {
  case pending, remaining {
    [], _ -> Ok(Nil)
    _, 0 -> Error("query did not reach a fixed point in 1000 rounds")
    _, _ -> {
      use grown <- result.try(
        list.try_fold(pending, set.new(), fn(grown, rule) {
          let sql.Rule(head:, statement: sql.Statement(text, params), ..) = rule
          use _ <- result.try(execute(connection, text, params))
          use changes <- result.map(query(connection, "SELECT changes()", []))
          case changes {
            [[sqlite.Integer(n)]] if n > 0 -> set.insert(grown, head)
            _ -> grown
          }
        }),
      )
      let pending =
        list.filter(all, fn(rule) {
          list.any(rule.reads, set.contains(grown, _))
        })
      rounds(connection, all, pending, remaining - 1)
    }
  }
}

fn read(connection, relation: sql.Relation) {
  let sql.Relation(label:, columns:) = relation
  use rows <- result.map(execute(connection, sql.select(relation), []))
  let rows =
    list.map(rows, fn(row) {
      case columns {
        [] -> v.unit()
        _ ->
          list.zip(columns, row)
          |> list.filter_map(fn(pair) {
            eyg_value(pair.1) |> result.map(fn(value) { #(pair.0, value) })
          })
          |> dict.from_list
          |> v.Record
      }
    })
  #(label, rows)
}

fn eyg_value(value) {
  case value {
    sqlite.Integer(i) -> Ok(v.Integer(i))
    sqlite.Text(s) -> Ok(v.String(s))
    sqlite.Blob(b) -> Ok(v.Binary(b))
    sqlite.Null -> Error(Nil)
  }
}
