//// Compile a typed EYG table into a SQLite fixed-point program and a client
//// whose result decoder is derived from the inferred selected relation.
//// SQL performs joins and set insertion; compiled pure EYG functions preserve
//// head/guard semantics. Snapshot rounds support mutual and nonlinear recursion,
//// which SQLite's single recursive CTE restrictions would otherwise exclude.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/compiler
import eyg/interpreter/budget
import eyg/interpreter/capture
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value
import eyg/ir/tree as ir
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/result.{try}
import gleam/string

pub type Column {
  Column(field: String, column: String, type_: binding.Mono)
}

pub type Source {
  Source(relation: String, table: String, columns: List(Column))
}

pub type Query {
  Query(
    result_type: binding.Mono,
    sql: List(String),
    javascript: String,
    typescript: String,
  )
}

type Rule {
  Rule(reads: List(String), function: String)
}

/// Sources supply the host's database-schema contract. They do not evaluate
/// or substitute query results: the generated client reads the real tables.
/// The expression must be a pure, closed table expression (bundle imports first).
pub fn to_sql(expression: ir.Node(a), relation: String, sources: List(Source)) {
  use source_json <- try(list.try_map(sources, source_json))
  use _ <- try(unique(
    list.map(sources, fn(s) { s.relation }),
    "source relation",
  ))
  let expression = ir.clear_annotation(expression)
  let context = infer.pure()
  let #(tail, bindings) = binding.mono(context.level, context.bindings)
  let expected =
    t.Table(t.do_rows(
      list.map(sources, fn(s) {
        #(
          s.relation,
          t.record(list.map(s.columns, fn(c) { #(c.field, c.type_) })),
        )
      }),
      tail,
    ))
  let context =
    infer.Context(..context, bindings:)
    |> infer.with_expected_type(expected)
  let checked = infer.check_with_references(context, dict.new(), expression)
  use _ <- try(case infer.all_errors(checked) {
    [] -> Ok(Nil)
    errors -> Error("query type error: " <> string.inspect(errors))
  })
  use rows <- try(case infer.type_(checked) {
    t.Table(rows) -> Ok(rows)
    _ -> Error("expected a Table")
  })
  use result_type <- try(relation_type(rows, relation))
  use result_schema <- try(schema(result_type))
  use typescript <- try(typescript_type(result_type))
  use #(facts, rules) <- try(
    case budget.start(expression, []) |> budget.advance(1_000_000) {
      budget.Run(state.Break(Ok(value.Table(facts, rules))), _) ->
        Ok(#(facts, rules))
      budget.Run(state.Break(Ok(_)), _) -> Error("expected a Table value")
      budget.Run(state.Break(Error(#(reason, _, _, _))), _) ->
        Error("cannot evaluate table: " <> simple_debug.describe(reason))
      _ -> Error("table construction exceeded 1000000 interpreter transitions")
    },
  )
  use rules <- try(list.try_map(rules, lower_rule))
  use _ <- try(list.try_map(dict.values(facts) |> list.flatten, data_value))
  let seeds =
    list.flat_map(dict.to_list(facts), fn(pair) {
      list.map(pair.1, fn(row) {
        "["
        <> quote(pair.0)
        <> ","
        <> compiled(capture.capture(row, Nil))
        <> "]"
      })
    })
    |> string.join(",\n")
  let rule_sql =
    list.index_map(rules, fn(rule, index) { insert_rule(rule.reads, index) })
  let plan =
    json.object([
      #("output", json.string(relation)),
      #("schema", result_schema),
      #("sources", json.array(source_json, fn(x) { x })),
      #(
        "rules",
        json.array(list.zip(rules, rule_sql), fn(pair) {
          json.object([
            #("reads", json.array(pair.0.reads, json.string)),
            #("sql", json.string(pair.1)),
          ])
        }),
      ),
    ])
  let javascript =
    "// Generated from a typed EYG Table. Regenerate instead of editing.\n"
    <> "const createClient = "
    <> runtime_source()
    <> ";\n"
    <> "const seeds = ["
    <> seeds
    <> "];\n"
    <> "const rules = ["
    <> string.join(list.map(rules, fn(r) { r.function }), ",\n")
    <> "];\n"
    <> "export const query = createClient("
    <> json.to_string(plan)
    <> ", seeds, rules);\n"
    <> "export const run = query.run;\nexport const decode = query.decode;\nexport const sql = query.sql;\n"
  let sql =
    list.map(sources, select_source)
    |> list.append(rule_sql)
    |> list.append(["SELECT value FROM \"%PREFIX%_facts\" WHERE relation = ?"])
  Ok(Query(
    result_type,
    sql,
    javascript,
    "import type { DatabaseSync } from 'node:sqlite';\n"
      <> "export type Row = "
      <> typescript
      <> ";\n"
      <> "export type Options = { maxRounds?: number; maxFacts?: number };\n"
      <> "export declare function run(db: DatabaseSync, options?: Options): Row[];\n"
      <> "export declare function decode(value: string): Row;\n"
      <> "export declare const sql: readonly string[];\n"
      <> "export declare const query: { run: typeof run; decode: typeof decode; sql: typeof sql };\n",
  ))
}

fn unique(names, kind) {
  case list.length(list.unique(names)) == list.length(names) {
    True -> Ok(Nil)
    False -> Error("duplicate " <> kind)
  }
}

fn data_value(value) {
  case value {
    value.Integer(_) | value.String(_) | value.Binary(_) -> Ok(Nil)
    value.Record(fields) -> {
      use _ <- try(list.try_map(dict.keys(fields), data_field))
      use _ <- try(list.try_map(dict.values(fields), data_value))
      Ok(Nil)
    }
    value.LinkedList(items) -> {
      use _ <- try(list.try_map(items, data_value))
      Ok(Nil)
    }
    value.Tagged(_, inner) -> data_value(inner)
    _ -> Error("only data values can be stored in SQL relations")
  }
}

fn data_field(name) {
  case string.starts_with(name, "$") {
    True -> Error("SQL record fields beginning with $ are reserved")
    False -> Ok(Nil)
  }
}

fn identifier(name) {
  "\"" <> string.replace(name, "\"", "\"\"") <> "\""
}

fn quote(value) {
  json.to_string(json.string(value))
}

fn source_json(source: Source) {
  use _ <- try(unique(
    list.map(source.columns, fn(c) { c.field }),
    "source field",
  ))
  use _ <- try(case source.columns {
    [] -> Error("a SQL source needs at least one column")
    _ -> Ok(Nil)
  })
  use columns <- try(
    list.try_map(source.columns, fn(column) {
      use _ <- try(data_field(column.field))
      use type_ <- try(schema(column.type_))
      use _ <- try(sql_column_type(column.type_))
      Ok(
        json.object([
          #("field", json.string(column.field)),
          #("type", type_),
        ]),
      )
    }),
  )
  use _ <- try(
    case
      list.any(
        [
          source.table,
          ..list.flat_map(source.columns, fn(c) { [c.column, c.field] })
        ],
        fn(name) { string.contains(name, "\u{0}") },
      )
    {
      True -> Error("SQL identifiers cannot contain NUL")
      False -> Ok(Nil)
    },
  )
  Ok(
    json.object([
      #("relation", json.string(source.relation)),
      #("sql", json.string(select_source(source))),
      #("columns", json.array(columns, fn(x) { x })),
    ]),
  )
}

fn select_source(source: Source) {
  "SELECT "
  <> string.join(
    list.map(source.columns, fn(column) {
      identifier(column.column) <> " AS " <> identifier(column.field)
    }),
    ", ",
  )
  <> " FROM "
  <> identifier(source.table)
}

fn boolean(type_) {
  case type_ {
    t.Union(rows) ->
      case fields(rows) {
        Ok(fields) ->
          list.length(fields) == 2
          && list.contains(fields, #("True", t.unit))
          && list.contains(fields, #("False", t.unit))
        _ -> False
      }
    _ -> False
  }
}

fn sql_scalar(type_) {
  case type_ {
    t.Integer | t.String | t.Binary -> Ok(Nil)
    _ ->
      case boolean(type_) {
        True -> Ok(Nil)
        False ->
          Error("SQL columns support scalar, Boolean, or Option scalar types")
      }
  }
}

fn sql_column_type(type_) {
  case sql_scalar(type_) {
    Ok(_) -> Ok(Nil)
    Error(_) -> sql_option(type_)
  }
}

fn sql_option(type_) {
  case type_ {
    t.Union(rows) -> {
      use fields <- try(fields(rows))
      case
        list.key_find(fields, "Some"),
        list.key_find(fields, "None"),
        list.length(fields)
      {
        Ok(inner), Ok(t.Record(t.Empty)), 2 -> sql_scalar(inner)
        _, _, _ ->
          Error("SQL columns support scalar, Boolean, or Option scalar types")
      }
    }
    _ -> Error("SQL columns support scalar, Boolean, or Option scalar types")
  }
}

fn relation_type(rows, wanted) {
  case rows {
    t.RowExtend(label, type_, _) if label == wanted -> Ok(type_)
    t.RowExtend(_, _, rest) -> relation_type(rest, wanted)
    _ -> Error("no inferred schema for relation " <> wanted)
  }
}

fn fields(rows) {
  case rows {
    t.Empty -> Ok([])
    t.RowExtend(name, type_, rest) -> {
      use rest <- try(fields(rest))
      Ok([#(name, type_), ..rest])
    }
    _ ->
      Error("query result schema is open; supply concrete source column types")
  }
}

fn schema(type_) {
  case type_ {
    t.Integer -> Ok(json.object([#("kind", json.string("integer"))]))
    t.String -> Ok(json.object([#("kind", json.string("string"))]))
    t.Binary -> Ok(json.object([#("kind", json.string("binary"))]))
    t.List(inner) -> {
      use inner <- try(schema(inner))
      Ok(json.object([#("kind", json.string("list")), #("item", inner)]))
    }
    t.Record(rows) -> {
      use row_fields <- try(fields(rows))
      use _ <- try(list.try_map(row_fields, fn(f) { data_field(f.0) }))
      row_schema("record", rows)
    }
    t.Union(rows) -> row_schema("union", rows)
    _ ->
      Error("unsupported or unresolved SQL result type: " <> debug.mono(type_))
  }
}

fn row_schema(kind, rows) {
  use fields <- try(fields(rows))
  use fields <- try(
    list.try_map(fields, fn(field) {
      use type_ <- try(schema(field.1))
      Ok(json.object([#("name", json.string(field.0)), #("type", type_)]))
    }),
  )
  Ok(
    json.object([
      #("kind", json.string(kind)),
      #("fields", json.array(fields, fn(x) { x })),
    ]),
  )
}

fn typescript_type(type_) {
  case type_ {
    t.Integer -> Ok("number")
    t.String -> Ok("string")
    t.Binary -> Ok("Uint8Array")
    t.List(inner) -> {
      use inner <- try(typescript_type(inner))
      Ok("Array<" <> inner <> ">")
    }
    t.Record(rows) -> {
      use fields <- try(fields(rows))
      use fields <- try(
        list.try_map(fields, fn(field) {
          use type_ <- try(typescript_type(field.1))
          Ok(quote(field.0) <> ": " <> type_)
        }),
      )
      Ok("{ " <> string.join(fields, "; ") <> " }")
    }
    t.Union(rows) -> {
      case boolean(type_) {
        True -> Ok("boolean")
        False -> typescript_union(rows)
      }
    }
    _ -> Error("unsupported TypeScript result type")
  }
}

fn typescript_union(rows) {
  use fields <- try(fields(rows))
  use fields <- try(
    list.try_map(fields, fn(field) {
      use type_ <- try(typescript_type(field.1))
      Ok("{ tag: " <> quote(field.0) <> "; value: " <> type_ <> " }")
    }),
  )
  Ok(string.join(fields, " | "))
}

fn apply(function, args) {
  list.fold(args, function, fn(f, arg) { ir.apply(f, arg) })
}

fn unapply(node) {
  do_unapply(node, [])
}

fn do_unapply(node, args) {
  case node {
    #(ir.Apply(f, arg), _) -> do_unapply(f, [arg, ..args])
    _ -> #(node, args)
  }
}

fn independent(node, database) {
  case list.contains(ir.free_variables(node, []), database) {
    True ->
      Error(
        "SQL requires positive relation clauses; snapshot inspection is unsupported",
      )
    False -> Ok(Nil)
  }
}

fn lower_rule(rule) {
  case rule {
    value.Closure(database, body, captured) -> {
      use #(body, reads) <- try(lower_body(body, database, []))
      let function =
        capture.capture(value.Closure(database, body, captured), Nil)
        |> ir.apply(ir.unit())
      let function = ir.lambda("$sqlUnit", function)
      let function =
        list.index_fold(list.reverse(reads), function, fn(fn_, _, index) {
          ir.lambda(
            "$sqlRow" <> int.to_string(list.length(reads) - 1 - index),
            fn_,
          )
        })
      Ok(Rule(reads, compiled(function)))
    }
    _ -> Error("SQL rules must be closures produced by query literals")
  }
}

// Recognize the parser's positive-rule lowering. Merely replacing every
// `resolve` with a singleton would miscompile aggregation over a whole snapshot.
fn lower_body(body, database, reads) {
  case body {
    #(ir.Let(name, value, then), _) -> {
      use _ <- try(independent(value, database))
      use #(then, reads) <- try(lower_body(then, database, reads))
      Ok(#(ir.let_(name, value, then), reads))
    }
    _ ->
      case unapply(body) {
        #(#(ir.Query(ir.Fact(_)), _), [payload]) -> {
          use _ <- try(independent(payload, database))
          Ok(#(body, reads))
        }
        #(
          #(ir.Builtin("list_fold"), _),
          [rows, #(ir.Query(ir.EmptyTable), _), fold],
        ) -> {
          case unapply(rows), fold {
            #(#(ir.Query(ir.Resolve(label)), _), [#(ir.Variable(db), _)]),
              #(ir.Lambda(row, #(ir.Lambda(acc, next), _)), _)
              if db == database
            -> {
              case unapply(next) {
                #(#(ir.Query(ir.Merge), _), [#(ir.Variable(a), _), next])
                  if a == acc
                -> {
                  let parameter = "$sqlRow" <> int.to_string(list.length(reads))
                  use #(next, reads) <- try(lower_body(
                    next,
                    database,
                    list.append(reads, [label]),
                  ))
                  Ok(#(ir.let_(row, ir.variable(parameter), next), reads))
                }
                _ -> Error("unsupported SQL rule fold accumulator")
              }
            }
            _, _ -> Error("unsupported SQL relation clause")
          }
        }
        #(#(ir.Case("True"), _), [#(ir.Lambda(unit, yes), _), no, condition]) -> {
          use _ <- try(independent(condition, database))
          case unapply(no) {
            #(
              #(ir.Case("False"), _),
              [
                #(ir.Lambda(_, #(ir.Query(ir.EmptyTable), _)), _),
                #(ir.NoCases, _),
              ],
            ) -> {
              use #(yes, reads) <- try(lower_body(yes, database, reads))
              Ok(#(
                apply(#(ir.Case("True"), Nil), [
                  ir.lambda(unit, yes),
                  no,
                  condition,
                ]),
                reads,
              ))
            }
            _ -> Error("unsupported SQL rule guard")
          }
        }
        _ ->
          Error("SQL requires rules constructed by the positive query syntax")
      }
  }
}

fn compiled(expression) {
  compiler.to_js_expression(
    expression,
    dict.new(),
    "(label) => { throw new Error('unexpected effect in SQL: ' + label); }",
  )
}

fn insert_rule(reads, index) {
  let aliases = list.index_map(reads, fn(_, i) { "r" <> int.to_string(i) })
  let arguments = string.join(list.map(aliases, fn(a) { a <> ".value" }), ", ")
  let from = list.map(aliases, fn(a) { "\"%PREFIX%_snapshot\" AS " <> a })
  let from =
    list.append(from, [
      "json_each(\"%PREFIX%_rule_"
      <> int.to_string(index)
      <> "\"("
      <> arguments
      <> ")) AS emitted",
    ])
  "INSERT OR IGNORE INTO \"%PREFIX%_facts\" (relation, value)\n"
  <> "SELECT json_extract(emitted.value, '$[0]'), json_extract(emitted.value, '$[1]')\nFROM "
  <> string.join(from, " CROSS JOIN ")
  <> case aliases {
    [] -> ""
    _ ->
      "\nWHERE "
      <> string.join(list.map(aliases, fn(a) { a <> ".relation = ?" }), " AND ")
  }
}

@external(javascript, "../../sql_runtime.mjs", "source")
fn runtime_source() -> String
