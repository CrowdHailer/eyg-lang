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
  string.concat([label, ": ", to_string(type_)])
}

pub fn to_string(monotype) {
  case monotype {
    Binary -> "Binary"
    Tuple(elements) ->
      string.concat([
        "(",
        string.join(list.map(elements, to_string), ", "),
        ")",
      ])
    Function(Row([#(l, Function(Tuple(ts), _))], _), _) ->
      string.join([l, ..list.map(ts, to_string)], "")
    Row(fields, _) ->
      string.concat([
        "{",
        string.join(list.map(fields, row_to_string), ", "),
        "}",
      ])
    Function(from, to) -> string.concat([to_string(from), " -> ", to_string(to)])
    Unbound(i) -> int.to_string(i)
  }
}

fn do_occurs_in(i, b) {
  case b {
    Unbound(j) if i == j -> True
    Unbound(_) -> False
    Binary -> False
    Function(from, to) -> do_occurs_in(i, from) || do_occurs_in(i, to)
    Tuple(elements) -> list.any(elements, do_occurs_in(i, _))
    Row(fields, _) ->
      fields
      |> list.map(fn(x: #(String, Monotype)) { x.1 })
      |> list.any(do_occurs_in(i, _))
  }
}

fn occurs_in(a, b) {
  case a {
    Unbound(i) ->
      case do_occurs_in(i, b) {
        True -> // TODO this very doesn't work
          // todo("Foo")
          True
        False -> False
      }
    _ -> False
  }
}

pub fn resolve(type_, substitutions) {
  case type_ {
    Unbound(i) ->
      case list.key_find(substitutions, i) {
        Ok(Unbound(j)) if i == j -> type_
        Error(Nil) -> type_
        Ok(substitution) -> {
          let False = occurs_in(Unbound(i), substitution)
          resolve(substitution, substitutions)
        }
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
        Some(i) -> {
          type_
          // TODO therese something wang with records
          case resolve(Unbound(i), substitutions) {
            Unbound(j) -> Row(resolved_fields, Some(j))
            Row(inner, rest) -> Row(list.append(resolved_fields, inner), rest)
            x -> {
              io.debug(x)
              todo("unifying")
            }
          }
        }
      }
    }
    // TODO check resolve in our record based recursive frunctions
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
