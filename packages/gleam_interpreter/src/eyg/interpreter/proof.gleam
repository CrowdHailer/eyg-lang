//// One finite, first-discovered witness for each query answer. These are
//// evaluation evidence, not authentication of the host's input facts.

import eyg/interpreter/table
import eyg/interpreter/value as v
import gleam/dict.{type Dict}
import gleam/list
import gleam/result

pub type Tree(m, c) {
  Fact(relation: String, row: v.Value(m, c))
  Rule(
    relation: String,
    row: v.Value(m, c),
    rule: Int,
    at: m,
    premises: List(Tree(m, c)),
  )
  /// A lowered query guard returned True. `at` identifies the predicate in
  /// source; bindings contain visible scalar values at the successful guard.
  Predicate(at: m, bindings: List(#(String, v.Value(m, c))))
}

pub type Query(m, c) {
  Query(relation: String, answers: List(#(v.Value(m, c), Tree(m, c))))
}

pub type Store(m, c) {
  Store(
    known: Dict(#(String, v.Value(m, c)), Tree(m, c)),
    candidates: Dict(#(String, v.Value(m, c)), Tree(m, c)),
  )
}

pub fn seed(facts: table.Facts(m, c)) -> Store(m, c) {
  let known =
    dict.fold(facts, dict.new(), fn(known, label, rows) {
      dict.fold(rows, known, fn(known, row, _) {
        dict.insert(known, #(label, row), Fact(label, row))
      })
    })
  Store(known, dict.new())
}

pub fn begin_rule(store: Store(m, c)) -> Store(m, c) {
  Store(..store, candidates: dict.new())
}

pub fn record(
  store: Store(m, c),
  label: String,
  row: v.Value(m, c),
  rule: Int,
  at: m,
  premises: List(Tree(m, c)),
) -> Store(m, c) {
  let key = #(label, row)
  case dict.has_key(store.known, key) || dict.has_key(store.candidates, key) {
    True -> store
    False ->
      Store(
        ..store,
        candidates: dict.insert(
          store.candidates,
          key,
          Rule(label, row, rule, at, premises),
        ),
      )
  }
}

/// Commit only facts actually returned by the completed rule. A candidate
/// constructed and then discarded by a pure rule is not a query answer.
pub fn commit(
  store: Store(m, c),
  returned: table.Facts(m, c),
  rule: Int,
  at: m,
) -> Store(m, c) {
  let known =
    dict.fold(returned, store.known, fn(known, label, rows) {
      dict.fold(rows, known, fn(known, row, _) {
        let key = #(label, row)
        case dict.has_key(known, key) {
          True -> known
          False -> {
            // A rule may return a preconstructed constant table without emitting
            // a new Fact call. Its completed rule is then a zero-premise witness.
            let tree =
              dict.get(store.candidates, key)
              |> result.unwrap(Rule(label, row, rule, at, []))
            dict.insert(known, key, tree)
          }
        }
      })
    })
  Store(known, dict.new())
}

pub fn lookup(
  store: Store(m, c),
  label: String,
  row: v.Value(m, c),
) -> Tree(m, c) {
  dict.get(store.known, #(label, row)) |> result.unwrap(Fact(label, row))
}

pub fn query(
  store: Store(m, c),
  label: String,
  facts: table.Facts(m, c),
) -> Query(m, c) {
  Query(
    label,
    list.map(table.rows(facts, label), fn(row) {
      #(row, lookup(store, label, row))
    }),
  )
}
