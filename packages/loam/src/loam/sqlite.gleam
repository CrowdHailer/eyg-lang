//// Run SQL planned from a query table against a SQLite database.
//// Rules are repeated until a round adds no facts. A rule only runs again
//// when a relation it reads grew in the previous round.

import eyg/compiler/sql
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import loam/system

pub fn execute(database, statement, params) {
  system.sql(database, statement, list.map(params, value))
}

fn value(param) {
  case param {
    sql.Integer(i) -> system.SqlInteger(i)
    sql.Text(s) -> system.SqlText(s)
    sql.Blob(b) -> system.SqlBlob(b)
  }
}

/// The derived relations, as EYG records, and the statements that were run.
pub fn resolve(database, plan: sql.Plan) {
  let sql.Plan(relations:, seeds:, rules:) = plan
  let log = []
  let tables = "SELECT name FROM main.sqlite_master WHERE type = 'table'"
  use existing <- system.then(execute(database, tables, []))
  use existing <- system.try(existing)
  let existing = list.flat_map(existing.rows, fn(row) { row })
  let drop = list.map(relations, sql.drop)
  use log <- then_each(database, drop, log)
  let create =
    list.flat_map(relations, fn(relation) {
      case list.contains(existing, system.SqlText(relation.label)) {
        True -> [sql.create(relation), sql.seed_from_main(relation)]
        False -> [sql.create(relation)]
      }
    })
  use outcome <- system.then({
    use log <- then_each(database, create, log)
    use log <- then_statements(database, seeds, log)
    let log =
      list.fold(rules, log, fn(log, rule) { [rule.statement.sql, ..log] })
    let all = list.index_map(rules, fn(rule, i) { #(i, rule) })
    use Nil <- try_then(rounds(database, all, all, 1000))
    use facts <- try_then(read(database, relations))
    system.Done(Ok(#(facts, list.reverse(log))))
  })
  use _ <- then_each(database, drop, [])
  system.Done(outcome)
}

fn then_each(database, statements, log, then) {
  case statements {
    [] -> then(log)
    [statement, ..rest] -> {
      use result <- system.then(execute(database, statement, []))
      case result {
        Ok(_) -> then_each(database, rest, [statement, ..log], then)
        Error(reason) -> system.Done(Error(reason <> " in " <> statement))
      }
    }
  }
}

fn then_statements(database, statements: List(sql.Statement), log, then) {
  case statements {
    [] -> then(log)
    [sql.Statement(text, params), ..rest] -> {
      use result <- system.then(execute(database, text, params))
      case result {
        Ok(_) -> then_statements(database, rest, [text, ..log], then)
        Error(reason) -> system.Done(Error(reason <> " in " <> text))
      }
    }
  }
}

fn rounds(database, all, pending, remaining) {
  case pending, remaining {
    [], _ -> system.Done(Ok(Nil))
    _, 0 ->
      system.Done(Error("query did not reach a fixed point in 1000 rounds"))
    _, _ -> {
      use grown <- try_then(round(database, pending, set.new()))
      let pending =
        list.filter(all, fn(pair) {
          let #(_, rule): #(Int, sql.Rule) = pair
          list.any(rule.reads, set.contains(grown, _))
        })
      rounds(database, all, pending, remaining - 1)
    }
  }
}

fn round(database, rules, grown) {
  case rules {
    [] -> system.Done(Ok(grown))
    [#(_, sql.Rule(head:, statement:, ..)), ..rest] -> {
      let sql.Statement(text, params) = statement
      use result <- system.then(execute(database, text, params))
      case result {
        Ok(system.SqlResult(changes:, ..)) if changes > 0 ->
          round(database, rest, set.insert(grown, head))
        Ok(_) -> round(database, rest, grown)
        Error(reason) -> system.Done(Error(reason <> " in " <> text))
      }
    }
  }
}

fn read(database, relations) {
  case relations {
    [] -> system.Done(Ok([]))
    [relation, ..rest] -> {
      let sql.Relation(label:, columns:) = relation
      use result <- try_then(execute(database, sql.select(relation), []))
      let rows =
        list.map(result.rows, fn(row) {
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
      use rest <- try_then(read(database, rest))
      system.Done(Ok([#(label, rows), ..rest]))
    }
  }
}

fn eyg_value(value) {
  case value {
    system.SqlInteger(i) -> Ok(v.Integer(i))
    system.SqlText(s) -> Ok(v.String(s))
    system.SqlBlob(b) -> Ok(v.Binary(b))
    system.SqlNull -> Error(Nil)
  }
}

fn try_then(effect, then) {
  use result <- system.then(effect)
  case result {
    Ok(value) -> then(value)
    Error(reason) -> system.Done(Error(reason))
  }
}
