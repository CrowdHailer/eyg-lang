import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string

pub type Monotype {
  Binary
  Tuple(elements: List(Monotype))
  Row(fields: List(#(String, Monotype)), extra: Option(Int))
  Function(from: Monotype, to: Monotype)
  Unbound(i: Int)
}

fn row_to_string(row) {
  let #(label, type_) = row
  string.join([label, ": ", to_string(type_)])
}

pub fn to_string(monotype) {
  case monotype {
    Binary -> "Binary"
    Tuple(elements) ->
      string.join([
        "(",
        string.join(list.intersperse(list.map(elements, to_string), ", ")),
        ")",
      ])
    Row(fields, _) ->
      string.join([
        "{",
        string.join(list.intersperse(list.map(fields, row_to_string), ", ")),
        "}",
      ])
    Function(from, to) -> string.join([to_string(from), " -> ", to_string(to)])
    Unbound(i) -> int.to_string(i)
  }
}

pub fn resolve(type_, substitutions) {
  case type_ {
    Unbound(i) ->
      case list.key_find(substitutions, i) {
        Ok(Unbound(j)) if i == j -> type_
        Error(Nil) -> type_
        Ok(substitution) -> resolve(substitution, substitutions)
      }
    Binary -> Binary
    Tuple(elements) -> {
      let elements = list.map(elements, resolve(_, substitutions))
      Tuple(elements)
    }
    Row(fields, rest) -> {
      let resolved_fields =
        list.map(
          fields,
          fn(field) {
            let #(name, type_) = field
            #(name, resolve(type_, substitutions))
          },
        )
      case rest {
        None -> Row(resolved_fields, None)
        Some(i) ->
          case resolve(Unbound(i), substitutions) {
            Unbound(j) -> Row(resolved_fields, Some(j))
            Row(inner, rest) -> Row(list.append(resolved_fields, inner), rest)
          }
      }
    }
    Function(from, to) -> {
      let from = resolve(from, substitutions)
      let to = resolve(to, substitutions)
      Function(from, to)
    }
  }
}

pub fn how_many_args(type_) {
  case type_ {
    Function(Tuple(elements), _) -> list.length(elements)
    _ -> 0
  }
}
