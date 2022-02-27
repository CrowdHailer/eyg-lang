import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string

pub type Monotype(n) {
  Native(n)
  Binary
  Tuple(elements: List(Monotype(n)))
  Record(fields: List(#(String, Monotype(n))), extra: Option(Int))
  Union(variants: List(#(String, Monotype(n))), extra: Option(Int))
  Function(from: Monotype(n), to: Monotype(n))
  Unbound(i: Int)
}

fn field_to_string(field, native_to_string) {
  let #(label, type_) = field
  string.concat([label, ": ", to_string(type_, native_to_string)])
}

pub fn to_string(monotype, native_to_string) {
  case monotype {
    Native(native) -> native_to_string(native)
    Binary -> "Binary"
    Tuple(elements) ->
      string.concat([
        "(",
        string.concat(list.intersperse(
          list.map(elements, to_string(_, native_to_string)),
          ", ",
        )),
        ")",
      ])
    Function(Record(fields, rest), return) -> {
      let all =
        list.try_map(
          fields,
          fn(f) {
            let #(name, type_) = f
            case type_ {
              Function(Tuple([]), x) if x == return -> Ok(name)
              Function(inner, x) if x == return ->
                Ok(string.concat([name, " ", to_string(inner, native_to_string)]))
              _ -> Error(Nil)
            }
          },
        )
      case all {
        Ok(variants) ->
          string.concat(["Variants ", ..list.intersperse(variants, " | ")])
        Error(Nil) -> {
          assert Function(from, to) = monotype
          string.concat([
            to_string(from, native_to_string),
            " -> ",
            to_string(to, native_to_string),
          ])
        }
      }
    }
    Record(fields, _) ->
      string.concat([
        "{",
        string.concat(list.intersperse(
          list.map(fields, field_to_string(_, native_to_string)),
          ", ",
        )),
        "}",
      ])
    Union(variants, _) -> "TODO finsih "
    Function(from, to) ->
      string.concat([
        to_string(from, native_to_string),
        " -> ",
        to_string(to, native_to_string),
      ])
    Unbound(i) -> int.to_string(i)
  }
}

pub fn literal(monotype) {
  case monotype {
    // Native(name) -> string.concat(["new T.Native(\"", name, "\")"])
    Binary -> "new T.Binary()"
    Tuple(elements) -> {
      let elements =
        list.map(elements, literal)
        |> list.intersperse(", ")
        |> string.concat
      string.concat(["new T.Tuple(Gleam.toList([", elements, "]))"])
    }
    Record(fields, extra) -> {
      let fields =
        list.map(
          fields,
          fn(f) {
            let #(name, value) = f
            string.concat(["[\"", name, "\", ", literal(value), "]"])
          },
        )
        |> list.intersperse(", ")
        |> string.concat
      let extra = case extra {
        Some(i) ->
          string.concat(["new Option.Some(", int.to_string(i + 1000), ")"])
        None -> "new Option.None()"
      }
      string.concat(["new T.Record(Gleam.toList([", fields, "]), ", extra, ")"])
    }
    Function(from, to) ->
      string.concat(["new T.Function(", literal(from), ",", literal(to), ")"])
    Unbound(i) -> string.concat(["new T.Unbound(", int.to_string(i), ")"])
    Native(_) | Union(_, _) -> todo("ss")
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
    Record(fields, _) ->
      fields
      |> list.map(fn(x: #(String, Monotype(a))) { x.1 })
      |> list.any(do_occurs_in(i, _))
    Union(_, _) -> False
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
          assert False = occurs_in(Unbound(i), substitution)
          resolve(substitution, substitutions)
        }
      }
    Native(name) -> Native(name)
    Binary -> Binary
    Tuple(elements) -> {
      let elements = list.map(elements, resolve(_, substitutions))
      Tuple(elements)
    }
    Record(fields, rest) -> {
      let resolved_fields =
        list.map(
          fields,
          fn(field) {
            let #(name, type_) = field
            #(name, resolve(type_, substitutions))
          },
        )
      case rest {
        None -> Record(resolved_fields, None)
        Some(i) -> {
          type_
          case resolve(Unbound(i), substitutions) {
            Unbound(j) -> Record(resolved_fields, Some(j))
            Record(inner, rest) ->
              Record(list.append(resolved_fields, inner), rest)
            _ ->
              todo("should only ever be one or the other. perhaps always an i")
          }
        }
      }
    }
    Union(variants, extra) -> {
      let resolved_variants =
        list.map(
          variants,
          fn(variant) {
            let #(name, type_) = variant
            #(name, resolve(type_, substitutions))
          },
        )
      case extra {
        None -> Union(resolved_variants, None)
        Some(i) -> {
          type_
          case resolve(Unbound(i), substitutions) {
            Unbound(j) -> Union(resolved_variants, Some(j))
            // TODO remove this and see if always works as i
            Union(inner, rest) ->
              Union(list.append(resolved_variants, inner), rest)
            _ ->
              todo("should only ever be one or the other. perhaps always an i")
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
