//// Sets of facts, one per relation. Each row maps to its insertion position so
//// membership is a lookup and results keep a repeatable order.

import eyg/interpreter/value as v
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set.{type Set}

pub type Facts(m, c) =
  Dict(String, Dict(v.Value(m, c), Int))

pub fn singleton(label, row) -> Facts(m, c) {
  dict.from_list([#(label, dict.from_list([#(row, 0)]))])
}

pub fn from_list(relations: List(#(String, List(v.Value(m, c))))) {
  list.fold(relations, dict.new(), fn(facts, relation) {
    let #(label, rows) = relation
    insert_all(facts, label, rows).0
  })
}

/// Rows of a relation in insertion order.
pub fn rows(facts: Facts(m, c), label) -> List(v.Value(m, c)) {
  case dict.get(facts, label) {
    Ok(relation) -> ordered(relation)
    Error(Nil) -> []
  }
}

fn ordered(relation) {
  dict.to_list(relation)
  |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
  |> list.map(fn(pair) { pair.0 })
}

pub fn to_list(facts: Facts(m, c)) {
  dict.to_list(facts)
  |> list.map(fn(pair) { #(pair.0, ordered(pair.1)) })
}

pub fn size(facts: Facts(m, c)) {
  dict.fold(facts, 0, fn(total, _, relation) { total + dict.size(relation) })
}

/// Add every fact of `right` to `left`, returning the relations that grew.
pub fn merge(
  left: Facts(m, c),
  right: Facts(m, c),
) -> #(Facts(m, c), Set(String)) {
  dict.fold(right, #(left, set.new()), fn(acc, label, relation) {
    let #(facts, changed) = acc
    case dict.get(facts, label) {
      Error(Nil) ->
        case dict.size(relation) {
          0 -> #(facts, changed)
          _ -> #(
            dict.insert(facts, label, relation),
            set.insert(changed, label),
          )
        }
      Ok(_) -> {
        let #(facts, grew) = insert_all(facts, label, ordered(relation))
        case grew {
          True -> #(facts, set.insert(changed, label))
          False -> #(facts, changed)
        }
      }
    }
  })
}

fn insert_all(facts, label, rows) {
  let relation = dict.get(facts, label) |> result.unwrap(dict.new())
  let before = dict.size(relation)
  let relation =
    list.fold(rows, relation, fn(relation, row) {
      case dict.has_key(relation, row) {
        True -> relation
        False -> dict.insert(relation, row, dict.size(relation))
      }
    })
  #(dict.insert(facts, label, relation), dict.size(relation) > before)
}

/// Group the rows of a relation by the record of their `keys` fields.
/// Rows that are not records with every key can never match and are left out.
pub fn index(facts: Facts(m, c), label, keys) {
  rows(facts, label)
  |> list.fold(dict.new(), fn(index, row) {
    case key(row, keys) {
      Ok(k) ->
        dict.upsert(index, k, fn(existing) {
          case existing {
            Some(rows) -> [row, ..rows]
            None -> [row]
          }
        })
      Error(Nil) -> index
    }
  })
  |> dict.map_values(fn(_, rows) { list.reverse(rows) })
}

pub fn key(row, keys) {
  case keys, row {
    [], _ -> Ok(v.Record(dict.new()))
    _, v.Record(fields) -> {
      use pairs <- result.map(
        list.try_map(keys, fn(k) {
          use value <- result.map(dict.get(fields, k))
          #(k, value)
        }),
      )
      v.Record(dict.from_list(pairs))
    }
    _, _ -> Error(Nil)
  }
}
