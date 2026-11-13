/// Embeds the bot/datalog EYG evaluator and the existing authorization/rbac
/// module. Only the host constructs input facts; requests cannot submit tables.
import eyg/interpreter/cast
import eyg/interpreter/explain
import eyg/interpreter/proof
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/table
import eyg/interpreter/value as v
import eyg/ir/tree
import eyg/parser
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub opaque type Engine {
  Engine(program: tree.Node(#(Int, Int)), transitions: Int, source: String)
}

pub fn load(path: String, transitions: Int) -> Result(Engine, String) {
  use source <- result.try(
    simplifile.read(path)
    |> result.replace_error("Cannot read EYG policy: " <> path),
  )
  compile(source, transitions)
}

/// Source must be a trusted module exporting `authorize(db, request)`.
pub fn compile(source: String, transitions: Int) -> Result(Engine, String) {
  let source = "let policy = " <> source <> "\npolicy.authorize(db, request)"
  parser.all_from_string(source)
  |> result.map(fn(program) { Engine(program, transitions, source) })
  |> result.map_error(fn(error) { parser.format_error(error, source) })
}

pub type Value =
  state.Value(#(Int, Int))

pub fn record(fields: List(#(String, Value))) -> Value {
  v.Record(dict.from_list(fields))
}

pub fn facts(relations: List(#(String, List(Value)))) -> Value {
  v.Table(table.from_list(relations), [])
}

/// Suspended, failed, effectful or malformed evaluation is never a permit.
pub fn authorize(
  engine: Engine,
  db: Value,
  request: Value,
) -> Result(List(#(String, String)), String) {
  authorize_with_proofs(engine, db, request)
  |> result.map(fn(permissions) {
    list.map(permissions, fn(permission) {
      #(permission.role, permission.policy)
    })
  })
}

pub type Permission {
  Permission(role: String, policy: String, tree: ProofTree)
}

/// Display projection of the native engine tree, preserving every premise and
/// field. `source` for predicates is the exact successful guard expression.
pub type ProofTree {
  ProofTree(
    kind: String,
    title: String,
    fields: List(#(String, String)),
    source: String,
    children: List(ProofTree),
  )
}

pub fn authorize_with_proofs(
  engine: Engine,
  db: Value,
  request: Value,
) -> Result(List(Permission), String) {
  let run = explain.start(engine.program, [#("db", db), #("request", request)])
  case explain.advance(run, engine.transitions) {
    explain.Suspended(_, _) -> Error("EYG policy evaluation budget exhausted")
    explain.Completed(Error(#(reason, _, _, _)), _) ->
      Error(simple_debug.describe(reason))
    explain.Completed(Ok(explained), _) -> {
      use rows <- result.try(
        cast.as_list(explained.value)
        |> result.map_error(simple_debug.describe),
      )
      let answers =
        explained.queries
        |> list.reverse
        |> list.find(fn(query) { query.relation == "Permit" })
        |> result.map(fn(query) { query.answers })
        |> result.unwrap([])
      list.try_map(rows, fn(row) {
        let fields = {
          use role <- result.try(cast.field("role", cast.as_string, row))
          use policy <- result.try(cast.field("policy", cast.as_string, row))
          Ok(#(role, policy))
        }
        use #(role, policy) <- result.try(
          fields |> result.map_error(simple_debug.describe),
        )
        use #(_, tree) <- result.try(
          list.find(answers, fn(answer) { answer.0 == row })
          |> result.replace_error("Permission has no engine-generated proof"),
        )
        Ok(Permission(role, policy, view(engine.source, tree)))
      })
    }
  }
}

fn fields(row) {
  case row {
    v.Record(fields) ->
      dict.to_list(fields)
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.map(fn(field) { #(field.0, simple_debug.inspect(field.1)) })
    _ -> [#("value", simple_debug.inspect(row))]
  }
}

fn view(
  source: String,
  tree: proof.Tree(#(Int, Int), state.Context(#(Int, Int))),
) -> ProofTree {
  case tree {
    proof.Fact(relation, row) ->
      ProofTree("fact", relation, fields(row), "", [])
    proof.Rule(relation, row, rule, _, premises) ->
      ProofTree(
        "rule",
        relation <> " [rule " <> int.to_string(rule) <> "]",
        fields(row),
        "",
        list.map(premises, view(source, _)),
      )
    proof.Predicate(at, bindings) ->
      ProofTree(
        "predicate",
        "Predicate passed",
        list.map(bindings, fn(pair) { #(pair.0, simple_debug.inspect(pair.1)) }),
        source_fragment(source, at),
        [],
      )
  }
}

fn source_fragment(source, at: #(Int, Int)) {
  // Parser spans are UTF-8 byte offsets, not grapheme/string.slice offsets.
  source
  |> bit_array.from_string
  |> bit_array.slice(at.0, at.1 - at.0)
  |> result.try(bit_array.to_string)
  |> result.unwrap("<source unavailable>")
}

pub fn describe(tree: ProofTree) -> String {
  describe_at(tree, "")
}

fn describe_at(tree: ProofTree, indent: String) -> String {
  let detail = case tree.kind {
    "predicate" -> tree.source <> " = True"
    _ -> tree.title
  }
  let bindings =
    tree.fields
    |> list.map(fn(pair) { pair.0 <> "=" <> pair.1 })
    |> string.join(", ")
  let children = list.map(tree.children, describe_at(_, indent <> "  "))
  string.join([indent <> detail, indent <> "  " <> bindings, ..children], "\n")
}
