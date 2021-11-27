import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string

pub type Monotype {
  Binary
  Tuple(elements: List(Monotype))
  Row(fields: List(#(String, Monotype)), extra: Option(Int))
  Nominal(name: String, of: List(Monotype))
  Function(from: Monotype, to: Monotype)
  Unbound(i: Int)
}

pub fn to_string(monotype) {
  case monotype {
    Binary -> "Binary"
    Tuple(elements) -> string.concat("Tuple", "TODO")
    Row(fields, _) -> string.concat("Row", "TODO")
    Function(_, _) -> string.concat("Function()", "TODO")
    Unbound(_) -> string.concat("a", "")
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
    Nominal(name, parameters) ->
      Nominal(name, list.map(parameters, resolve(_, substitutions)))
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
