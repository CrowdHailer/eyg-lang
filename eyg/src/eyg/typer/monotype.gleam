import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string

pub type Monotype(n) {
  Native(n)
  Binary
  Tuple(elements: List(Monotype(n)))
  Row(fields: List(#(String, Monotype(n))), extra: Option(Int))
  Function(from: Monotype(n), to: Monotype(n))
  Unbound(i: Int)
}

fn row_to_string(row, native_to_string) {
  let #(label, type_) = row
  string.join([label, ": ", to_string(type_, native_to_string)])
}

pub fn to_string(monotype, native_to_string) {
  case monotype {
    Native(native) -> native_to_string(native)
    Binary -> "Binary"
    Tuple(elements) ->
      string.join([
        "(",
        string.join(list.intersperse(
          list.map(elements, to_string(_, native_to_string)),
          ", ",
        )),
        ")",
      ])
    Function(Row(fields, rest), return) -> {
      let all =
        list.try_map(
          fields,
          fn(f) {
            let #(name, type_) = f
            case type_ {
              Function(Tuple([]), x) if x == return -> Ok(name)
              Function(inner, x) if x == return ->
                Ok(string.join([name, " ", to_string(inner, native_to_string)]))
              _ -> Error(Nil)
            }
          },
        )
      case all {
        Ok(variants) ->
          string.join(["Variants ", ..list.intersperse(variants, " | ")])
        Error(Nil) -> {
          let Function(from, to) = monotype
          string.join([
            to_string(from, native_to_string),
            " -> ",
            to_string(to, native_to_string),
          ])
        }
      }
    }
    Row(fields, _) ->
      string.join([
        "{",
        string.join(list.intersperse(
          list.map(fields, row_to_string(_, native_to_string)),
          ", ",
        )),
        "}",
      ])
    Function(from, to) ->
      string.join([
        to_string(from, native_to_string),
        " -> ",
        to_string(to, native_to_string),
      ])
    Unbound(i) -> int.to_string(i)
  }
}

pub fn literal(monotype) {
  case monotype {
    // Native(name) -> string.join(["new T.Native(\"", name, "\")"])
    Binary -> "new T.Binary()"
    Tuple(elements) -> {
      let elements =
        list.map(elements, literal)
        |> list.intersperse(", ")
        |> string.join
      string.join(["new T.Tuple(Gleam.toList([", elements, "]))"])
    }
    Row(fields, extra) -> {
      let fields =
        list.map(
          fields,
          fn(f) {
            let #(name, value) = f
            string.join(["[\"", name, "\", ", literal(value), "]"])
          },
        )
        |> list.intersperse(", ")
        |> string.join
      let extra = case extra {
        Some(i) ->
          string.join(["new Option.Some(", int.to_string(i + 1000), ")"])
        None -> "new Option.None()"
      }
      string.join(["new T.Row(Gleam.toList([", fields, "]), ", extra, ")"])
    }
    Function(from, to) ->
      string.join(["new T.Function(", literal(from), ",", literal(to), ")"])
    Unbound(i) -> string.join(["new T.Unbound(", int.to_string(i), ")"])
  }
}

fn do_occurs_in(i, b) {
  case b {
    Unbound(j) if i == j -> True
    Unbound(_) -> False
    Native(_) -> False
    Binary -> False
    Function(from, to) -> do_occurs_in(i, from) || do_occurs_in(i, to)
    Tuple(elements) -> list.any(elements, do_occurs_in(i, _))
    Row(fields, _) ->
      fields
      |> list.map(fn(x: #(String, Monotype(a))) { x.1 })
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
    Native(name) -> Native(name)
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
          case resolve(Unbound(i), substitutions) {
            Unbound(j) -> Row(resolved_fields, Some(j))
            Row(inner, rest) -> Row(list.append(resolved_fields, inner), rest)
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
