//// Plan an evaluated EYG table as SQL for SQLite.
////
//// Each rule's clauses become one `INSERT ... SELECT` with real joins: the
//// `Match` keys become join and filter conditions, so the database's indexes
//// and query planner do the work. Rule closures are partially evaluated:
//// captured values and helper functions are inlined, and `equal`,
//// `int_compare`, arithmetic and string appends become SQL expressions.
//// Relations named by rule heads or inline facts are temporary tables, every
//// other relation is read from the database table of the same name.

import eyg/interpreter/table
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/order
import gleam/result.{try}
import gleam/string

pub type Param {
  Integer(Int)
  Text(String)
  Blob(BitArray)
}

pub type Statement {
  Statement(sql: String, params: List(Param))
}

/// A temporary relation and its columns, the record fields of its rows.
pub type Relation {
  Relation(label: String, columns: List(String))
}

pub type Rule {
  Rule(reads: List(String), head: String, statement: Statement)
}

pub type Plan {
  Plan(relations: List(Relation), seeds: List(Statement), rules: List(Rule))
}

pub fn identifier(name) {
  "\"" <> string.replace(name, "\"", "\"\"") <> "\""
}

fn columns(names) {
  list.map(names, identifier) |> string.join(", ")
}

/// Rows of a temporary relation are a set, duplicates are ignored on insert.
pub fn create(relation: Relation) {
  let Relation(label, cols) = relation
  let unique = case cols {
    [] -> ""
    _ -> ", UNIQUE (" <> columns(cols) <> ")"
  }
  let cols = case cols {
    [] -> "\"$unit\" INTEGER DEFAULT 0"
    _ -> columns(cols)
  }
  "CREATE TEMP TABLE " <> identifier(label) <> " (" <> cols <> unique <> ")"
}

pub fn drop(relation: Relation) {
  "DROP TABLE IF EXISTS temp." <> identifier(relation.label)
}

/// Copy rows of a database table into the temporary relation that shadows it.
pub fn seed_from_main(relation: Relation) {
  let Relation(label, cols) = relation
  "INSERT OR IGNORE INTO temp."
  <> identifier(label)
  <> " ("
  <> columns(cols)
  <> ") SELECT "
  <> columns(cols)
  <> " FROM main."
  <> identifier(label)
}

pub fn select(relation: Relation) {
  let Relation(label, cols) = relation
  let cols = case cols {
    [] -> "\"$unit\""
    _ -> columns(cols)
  }
  "SELECT " <> cols <> " FROM temp." <> identifier(label)
}

pub fn plan(table: table.Facts(m, c), rules: List(v.Value(m, c))) {
  use planned <- try(
    list.index_map(rules, fn(rule, i) { #(i, rule) })
    |> list.try_map(fn(pair) {
      plan_rule(pair.1)
      |> result.map_error(fn(reason) {
        "rule " <> int.to_string(pair.0 + 1) <> ": " <> reason
      })
    }),
  )
  let rules = list.filter(planned, fn(rule) { rule.0 != "" })
  use facts <- try(
    table.to_list(table)
    |> list.try_map(fn(relation) {
      let #(label, rows) = relation
      use rows <- try(list.try_map(rows, fact_row))
      Ok(#(label, rows))
    }),
  )
  let fields =
    list.fold(rules, dict.new(), fn(acc, rule) {
      add_fields(acc, rule.0, list.map(rule.1, fn(c) { c.0 }))
    })
  let fields =
    list.fold(facts, fields, fn(acc, relation) {
      list.fold(relation.1, add_fields(acc, relation.0, []), fn(acc, row) {
        add_fields(acc, relation.0, list.map(row, fn(c) { c.0 }))
      })
    })
  let relations =
    dict.to_list(fields)
    |> list.map(fn(pair) { Relation(pair.0, list.sort(pair.1, string.compare)) })
    |> list.sort(fn(a, b) { string.compare(a.label, b.label) })
  let seeds =
    list.flat_map(facts, fn(relation) {
      list.map(relation.1, fn(row) {
        let row = list.sort(row, fn(a, b) { string.compare(a.0, b.0) })
        Statement(
          "INSERT OR IGNORE INTO temp."
            <> identifier(relation.0)
            <> " ("
            <> columns(list.map(row, fn(c) { c.0 }))
            <> ") VALUES ("
            <> list.map(row, fn(_) { "?" }) |> string.join(", ")
            <> ")",
          list.map(row, fn(c) { c.1 }),
        )
      })
    })
    |> list.map(fn(statement) {
      case statement.params {
        [] ->
          Statement(
            ..statement,
            sql: string.replace(
              statement.sql,
              " () VALUES ()",
              " DEFAULT VALUES",
            ),
          )
        _ -> statement
      }
    })
  let rules =
    list.map(rules, fn(rule) {
      let #(head, selected, from, where, reads) = rule
      Rule(reads, head, insert(head, selected, from, where))
    })
  Ok(Plan(relations, seeds, rules))
}

fn add_fields(acc, label, fields) {
  let existing = dict.get(acc, label) |> result.unwrap([])
  dict.insert(acc, label, list.unique(list.append(existing, fields)))
}

fn fact_row(row) {
  case row {
    v.Record(fields) ->
      dict.to_list(fields)
      |> list.try_map(fn(field) {
        use param <- try(param(field.1))
        Ok(#(field.0, param))
      })
    _ -> Error("facts stored in SQL must be records")
  }
}

fn param(value) {
  case value {
    v.Integer(i) -> Ok(Integer(i))
    v.String(s) -> Ok(Text(s))
    v.Binary(b) -> Ok(Blob(b))
    v.Tagged("True", _) -> Ok(Integer(1))
    v.Tagged("False", _) -> Ok(Integer(0))
    _ ->
      Error("only integers, strings, binaries and booleans can be SQL values")
  }
}

fn insert(
  head,
  selected: List(#(String, Fragment)),
  from: List(#(String, String)),
  where: List(Fragment),
) {
  let selected = list.sort(selected, fn(a, b) { string.compare(a.0, b.0) })
  let #(names, values) = list.unzip(selected)
  let from = list.reverse(from)
  let where = list.reverse(where)
  let target = case names {
    [] -> " DEFAULT VALUES"
    _ -> " (" <> columns(names) <> ")"
  }
  let projection = case values {
    [] -> "0"
    _ -> list.map(values, fn(f) { f.0 }) |> string.join(", ")
  }
  let from_sql =
    list.map(from, fn(f) { identifier(f.1) <> " AS " <> f.0 })
    |> string.join(", ")
  let where_sql = case where {
    [] -> ""
    _ ->
      " WHERE "
      <> list.map(where, fn(f: Fragment) { f.0 }) |> string.join(" AND ")
  }
  let body = case from {
    [] -> "SELECT DISTINCT " <> projection <> where_sql
    _ -> "SELECT DISTINCT " <> projection <> " FROM " <> from_sql <> where_sql
  }
  let sql = case names {
    // A relation of empty records holds at most one row.
    [] ->
      "INSERT OR IGNORE INTO temp."
      <> identifier(head)
      <> " (\"$unit\") "
      <> body
    _ ->
      "INSERT OR IGNORE INTO temp." <> identifier(head) <> target <> " " <> body
  }
  let params =
    list.flat_map(values, fn(f) { f.1 })
    |> list.append(list.flat_map(where, fn(f) { f.1 }))
  Statement(sql, params)
}

// --- Partial evaluation of rule closures ---

/// SQL text with its positional parameters.
type Fragment =
  #(String, List(Param))

type Sym(m, c) {
  Known(v.Value(m, c))
  // A scalar or boolean SQL expression.
  Sql(Fragment)
  // The result of comparing two SQL expressions, Lt, Eq or Gt.
  Comparison(Fragment, Fragment)
  Row(alias: String)
  Fields(List(#(String, Sym(m, c))))
  Variant(String, Sym(m, c))
  Lambda(String, ir.Node(m), List(#(String, Sym(m, c))))
  Op(Operation, List(Sym(m, c)))
  // The value of a branch that cannot be taken.
  Unreachable
  // The snapshot of the database passed to the rule.
  Database
}

type Operation {
  Builtin(String)
  Select(String)
  Extend(String)
  Tag(String)
  Case(String)
  NoCases
  Query(ir.QueryOperation)
}

type State {
  State(
    from: List(#(String, String)),
    where: List(Fragment),
    reads: List(String),
  )
}

fn plan_rule(rule) {
  case rule {
    v.Closure(param, body, env) -> {
      let scope = [
        #(param, Database),
        ..list.map(env, fn(p) { #(p.0, Known(p.1)) })
      ]
      use #(head, selected, state) <- try(clauses(
        body,
        scope,
        State([], [], []),
      ))
      Ok(#(head, selected, state.from, state.where, list.unique(state.reads)))
    }
    _ -> Error("rules must be closures produced by query literals")
  }
}

// Walk the rule body as lowered by the parser: matches, guards, unwrapped
// variants and lets, ending at the fact for the head.
fn clauses(node: ir.Node(m), scope, state: State) {
  case node.0 {
    ir.Let(name, value, then) -> {
      use value <- try(eval(value, scope))
      clauses(then, [#(name, value), ..scope], state)
    }
    _ -> {
      let #(f, args) = unapply(node, [])
      use f <- try(eval(f, scope))
      case f, args {
        Op(Query(ir.Match(label, keys)), []), [db, key, then] -> {
          use db <- try(eval(db, scope))
          use <- require(
            db == Database,
            "matches must read the rule's database",
          )
          use key <- try(eval(key, scope))
          use key <- try(record_fields(key))
          let alias = "t" <> int.to_string(list.length(state.from))
          use conditions <- try(
            list.try_map(keys, fn(field) {
              use value <- try(
                list.key_find(key, field)
                |> result.replace_error("missing key " <> field),
              )
              use value <- try(fragment(value))
              Ok(#(column(alias, field).0 <> " = " <> value.0, value.1))
            }),
          )
          let state =
            State(
              from: [#(alias, label), ..state.from],
              where: list.append(list.reverse(conditions), state.where),
              reads: [label, ..state.reads],
            )
          case then.0 {
            ir.Lambda(row, then) ->
              clauses(then, [#(row, Row(alias)), ..scope], state)
            _ -> Error("expected a function for the matched row")
          }
        }
        Op(Case(label), []), [branch, otherwise, value] -> {
          use value <- try(eval(value, scope))
          case label, value, branch.0 {
            "True", Sql(condition), ir.Lambda(_, then) ->
              clauses(
                then,
                scope,
                State(..state, where: [condition, ..state.where]),
              )
            _, Known(v.Tagged(tag, inner)), ir.Lambda(name, then)
              if tag == label
            -> clauses(then, [#(name, Known(inner)), ..scope], state)
            _, Variant(tag, inner), ir.Lambda(name, then) if tag == label ->
              clauses(then, [#(name, inner), ..scope], state)
            _, Known(v.Tagged(_, _)), _ | _, Variant(_, _), _ ->
              clauses(
                #(
                  ir.Apply(otherwise, #(ir.Variable("$value"), otherwise.1)),
                  otherwise.1,
                ),
                [#("$value", value), ..scope],
                state,
              )
            _, _, _ ->
              Error(
                "cannot match on a value computed by the database: " <> label,
              )
          }
        }
        Op(Query(ir.Fact(label)), []), [payload] -> {
          use payload <- try(eval(payload, scope))
          use fields <- try(record_fields(payload))
          use selected <- try(
            list.try_map(fields, fn(field) {
              use value <- try(fragment(field.1))
              Ok(#(field.0, value))
            }),
          )
          Ok(#(label, selected, state))
        }
        Op(Query(ir.EmptyTable), []), [] -> never(state)
        Lambda(param, body, captured), [arg] -> {
          use arg <- try(eval(arg, scope))
          clauses(body, [#(param, arg), ..captured], state)
        }
        _, _ -> Error("unsupported rule body")
      }
    }
  }
}

// A rule that reaches an empty table derives nothing, it has no statement.
fn never(state) {
  Ok(#("", [], state))
}

fn require(condition, message, then) {
  case condition {
    True -> then()
    False -> Error(message)
  }
}

fn unapply(node: ir.Node(m), args) {
  case node.0 {
    ir.Apply(f, a) -> unapply(f, [a, ..args])
    _ -> #(node, args)
  }
}

fn column(alias, field) -> Fragment {
  #(alias <> "." <> identifier(field), [])
}

fn record_fields(sym) {
  case sym {
    Fields(fields) -> Ok(fields)
    Known(v.Record(fields)) ->
      Ok(dict.to_list(fields) |> list.map(fn(p) { #(p.0, Known(p.1)) }))
    _ -> Error("expected a record")
  }
}

fn fragment(sym) -> Result(Fragment, String) {
  case sym {
    Sql(fragment) -> Ok(fragment)
    Known(value) -> {
      use param <- try(param(value))
      Ok(#("?", [param]))
    }
    _ -> Error("value cannot be represented in SQL")
  }
}

fn eval(node: ir.Node(m), scope) -> Result(Sym(m, c), String) {
  case node.0 {
    ir.Variable(name) ->
      list.key_find(scope, name)
      |> result.replace_error("unknown variable " <> name)
    ir.Lambda(param, body) -> Ok(Lambda(param, body, scope))
    ir.Apply(f, a) -> {
      use f <- try(eval(f, scope))
      use a <- try(eval(a, scope))
      call(f, a)
    }
    ir.Let(name, value, then) -> {
      use value <- try(eval(value, scope))
      eval(then, [#(name, value), ..scope])
    }
    ir.Integer(i) -> Ok(Known(v.Integer(i)))
    ir.String(s) -> Ok(Known(v.String(s)))
    ir.Binary(b) -> Ok(Known(v.Binary(b)))
    ir.Empty -> Ok(Known(v.unit()))
    ir.Extend(label) -> Ok(Op(Extend(label), []))
    ir.Select(label) -> Ok(Op(Select(label), []))
    ir.Tag(label) -> Ok(Op(Tag(label), []))
    ir.Case(label) -> Ok(Op(Case(label), []))
    ir.NoCases -> Ok(Op(NoCases, []))
    ir.Builtin(id) -> Ok(Op(Builtin(id), []))
    ir.Query(operation) -> Ok(Op(Query(operation), []))
    _ -> Error("unsupported expression in rule")
  }
}

fn call(f, a) -> Result(Sym(m, c), String) {
  case f {
    Lambda(param, body, scope) -> eval(body, [#(param, a), ..scope])
    Known(v.Closure(param, body, env)) ->
      eval(body, [#(param, a), ..list.map(env, fn(p) { #(p.0, Known(p.1)) })])
    Op(operation, args) -> operate(operation, list.append(args, [a]))
    _ -> Error("cannot call this value in SQL")
  }
}

fn operate(operation, args) {
  case operation, args {
    Select(label), [Row(alias)] -> Ok(Sql(column(alias, label)))
    Select(label), [record] -> {
      use fields <- try(record_fields(record))
      list.key_find(fields, label)
      |> result.replace_error("missing field " <> label)
    }
    Extend(label), [Known(value), Known(v.Record(fields))] ->
      Ok(Known(v.Record(dict.insert(fields, label, value))))
    Extend(label), [value, record] -> {
      use fields <- try(record_fields(record))
      Ok(
        Fields([#(label, value), ..list.filter(fields, fn(f) { f.0 != label })]),
      )
    }
    Tag(label), [Known(value)] -> Ok(Known(v.Tagged(label, value)))
    Tag(label), [value] -> Ok(Variant(label, value))
    Case(label), [branch, otherwise, value] ->
      branch_on(label, branch, otherwise, value)
    // Every variant of a value the database computed has a branch.
    NoCases, [_] -> Ok(Unreachable)
    Builtin(id), _ -> builtin(id, args)
    _, _ -> Ok(Op(operation, args))
  }
}

fn branch_on(label, branch, otherwise, value) {
  case value {
    Known(v.Tagged(tag, inner)) if tag == label -> call(branch, Known(inner))
    Variant(tag, inner) if tag == label -> call(branch, inner)
    Known(v.Tagged(_, _)) | Variant(_, _) -> call(otherwise, value)
    // A boolean computed by SQL.
    Sql(condition) -> {
      use yes <- try(call(branch, Known(v.unit())))
      use no <- try(call(otherwise, value))
      let condition = case label {
        "True" -> condition
        "False" -> #("NOT " <> condition.0, condition.1)
        _ -> #("0", [])
      }
      choose(condition, yes, no)
    }
    Comparison(left, right) -> {
      let operator = case label {
        "Lt" -> " < "
        "Eq" -> " = "
        "Gt" -> " > "
        _ -> " AND 0 AND "
      }
      let condition = #(
        "(" <> left.0 <> operator <> right.0 <> ")",
        list.append(left.1, right.1),
      )
      use yes <- try(call(branch, Known(v.unit())))
      use no <- try(call(otherwise, value))
      choose(condition, yes, no)
    }
    _ -> Error("cannot match on this value in SQL")
  }
}

// Only boolean results can be chosen by a condition the database decides.
fn choose(condition: Fragment, yes, no) {
  use <- bool.guard(no == Unreachable, Ok(yes))
  use <- bool.guard(yes == Unreachable, Ok(no))
  use yes <- try(boolean(yes))
  use no <- try(boolean(no))
  use <- bool.guard(yes == #("1", []) && no == #("0", []), Ok(Sql(condition)))
  let negated = #("NOT " <> condition.0, condition.1)
  use <- bool.guard(yes == #("0", []) && no == #("1", []), Ok(Sql(negated)))
  Ok(
    Sql(#(
      "(("
        <> condition.0
        <> " AND "
        <> yes.0
        <> ") OR (NOT "
        <> condition.0
        <> " AND "
        <> no.0
        <> "))",
      list.flatten([condition.1, yes.1, condition.1, no.1]),
    )),
  )
}

fn boolean(sym) -> Result(Fragment, String) {
  case sym {
    Known(v.Tagged("True", _)) -> Ok(#("1", []))
    Known(v.Tagged("False", _)) -> Ok(#("0", []))
    Sql(fragment) -> Ok(fragment)
    _ -> Error("expected a boolean")
  }
}

fn builtin(id, args) {
  case id, args {
    "equal", [Known(a), Known(b)] ->
      Ok(
        Known(case a == b {
          True -> v.true()
          False -> v.false()
        }),
      )
    "equal", [a, b] -> binary(a, b, " = ")
    "int_compare", [Known(v.Integer(a)), Known(v.Integer(b))] ->
      Ok(
        Known(case int.compare(a, b) {
          order.Lt -> v.Tagged("Lt", v.unit())
          order.Eq -> v.Tagged("Eq", v.unit())
          order.Gt -> v.Tagged("Gt", v.unit())
        }),
      )
    "int_compare", [a, b] -> {
      use a <- try(fragment(a))
      use b <- try(fragment(b))
      Ok(Comparison(a, b))
    }
    "int_add", [a, b] -> binary(a, b, " + ")
    "int_subtract", [a, b] -> binary(a, b, " - ")
    "int_multiply", [a, b] -> binary(a, b, " * ")
    "string_append", [a, b] -> binary(a, b, " || ")
    "equal", _
    | "int_compare", _
    | "int_add", _
    | "int_subtract", _
    | "int_multiply", _
    | "string_append", _
    -> Ok(Op(Builtin(id), args))
    _, _ -> Error("builtin !" <> id <> " is not available in SQL")
  }
}

fn binary(a, b, operator) {
  use a <- try(fragment(a))
  use b <- try(fragment(b))
  Ok(Sql(#("(" <> a.0 <> operator <> b.0 <> ")", list.append(a.1, b.1))))
}
