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
  Recursive(i: Int, type_: Monotype(n))
}

fn field_to_string(field, native_to_string) {
  let #(label, type_) = field
  string.concat([label, ": ", to_string(type_, native_to_string)])
}

fn variant_to_string(variant, native_to_string) {
  let #(label, type_) = variant
  string.concat([label, " ", to_string(type_, native_to_string)])
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
    Record(fields, extra) -> {
      let extra = case extra {
        Some(i) -> [string.concat(["..", int.to_string(i)])]
        None -> []
      }
      string.concat([
        "{",
        string.concat(list.intersperse(
          list.map(fields, field_to_string(_, native_to_string))
          |> list.append(extra),
          ", ",
        )),
        "}",
      ])
    }
    Union(variants, extra) -> {
      let extra = case extra {
        Some(i) -> [string.concat(["..", int.to_string(i)])]
        None -> []
      }
      string.concat([
        "[",
        string.concat(list.intersperse(
          list.map(variants, variant_to_string(_, native_to_string))
          |> list.append(extra),
          " | ",
        )),
        "]",
      ])
    }
    Function(from, to) ->
      string.concat([
        to_string(from, native_to_string),
        " -> ",
        to_string(to, native_to_string),
      ])
    Unbound(i) -> int.to_string(i)
    Recursive(i, inner) -> {
      let inner = to_string(inner, native_to_string)
      string.concat(["μ", int.to_string(i), ".", inner])
    }
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
    Native(_) | Union(_, _) | Recursive(_, _) -> todo("ss literal")
  }
}

pub fn do_resolve(type_, substitutions: List(#(Int, Monotype(n))), recuring) {
  case type_ {
    Native(s) -> Native(s)
    Unbound(i) ->
      case list.find(recuring, fn(j) { i == j }) {
        Ok(_) -> type_
        Error(Nil) ->
          case list.key_find(substitutions, i) {
            Ok(Unbound(j)) if i == j -> type_
            Error(Nil) -> type_
            Ok(sub) -> {
              let inner = do_resolve(sub, substitutions, [i, ..recuring])
              let recursive = list.contains(free_in_type(inner), i)
              case recursive {
                False -> inner
                True -> Recursive(i, inner)
              }
            }
          }
      }
    // This needs to exist as might already have been called by generalize
    Recursive(i, inner) -> {
      // case list.key_find(substitutions, i) {
      //   // TODO maybe never
      //   Ok(_) -> Unbound(i)
      //   Error(Nil) -> {
      let inner = do_resolve(inner, substitutions, [i, ..recuring])
      Recursive(i, inner)
    }
    // }
    // }
    Binary -> Binary
    Tuple(elements) -> {
      let elements = list.map(elements, do_resolve(_, substitutions, recuring))
      Tuple(elements)
    }
    Record(fields, rest) -> {
      let resolved_fields =
        list.map(
          fields,
          fn(field) {
            let #(name, type_) = field
            #(name, do_resolve(type_, substitutions, recuring))
          },
        )
      case rest {
        None -> Record(resolved_fields, None)
        Some(i) -> {
          type_
          case do_resolve(Unbound(i), substitutions, recuring) {
            Unbound(j) -> Record(resolved_fields, Some(j))
            Record(inner, rest) ->
              Record(list.append(resolved_fields, inner), rest)
            x -> {
              io.debug(substitutions)
              io.debug(recuring)
              io.debug(x)
              todo("should never have matched")
            }
          }
        }
      }
    }
    Union(variants, rest) -> {
      let resolved_variants =
        // TODO map_value would help or a resolve_named unify_named etc probably also sensible
        list.map(
          variants,
          fn(variant) {
            let #(name, type_) = variant
            #(name, do_resolve(type_, substitutions, recuring))
          },
        )
      case rest {
        None -> Union(resolved_variants, None)
        Some(i) -> {
          type_
          case do_resolve(Unbound(i), substitutions, recuring) {
            Unbound(j) -> Union(resolved_variants, Some(j))
            Union(inner, rest) ->
              Union(list.append(resolved_variants, inner), rest)
            x -> {
              io.debug(recuring)
              io.debug(x)
              todo("improper union")
            }
          }
        }
      }
    }
    Function(from, to) -> {
      let from = do_resolve(from, substitutions, recuring)
      let to = do_resolve(to, substitutions, recuring)
      Function(from, to)
    }
  }
}

pub fn resolve(t, substitutions) {
  do_resolve(t, substitutions, [])
}

// relies on type having been resolved
fn do_free_in_type(set, type_) {
  case type_ {
    Unbound(i) -> push_new(i, set)
    Native(_) | Binary -> set
    Tuple(elements) -> list.fold(elements, set, do_free_in_type)
    Record(rows, rest) | Union(rows, rest) -> do_free_in_row(rows, rest, set)
    Recursive(i, type_) -> {
      let inner = do_free_in_type(set, type_)
      difference(inner, [i])
    }
    Function(from, to) -> {
      let set = do_free_in_type(set, from)
      do_free_in_type(set, to)
    }
  }
}

fn do_free_in_row(rows, rest, set) {
  let set =
    list.fold(
      rows,
      set,
      fn(set, row) {
        let #(_name, type_) = row
        do_free_in_type(set, type_)
      },
    )
  case rest {
    None -> set
    // Already resolved
    Some(i) -> push_new(i, set)
  }
}

pub fn free_in_type(t) {
  do_free_in_type([], t)
}

// Set
fn push_new(item: a, set: List(a)) -> List(a) {
  case list.find(set, fn(i) { i == item }) {
    Ok(_) -> set
    Error(Nil) -> [item, ..set]
  }
}

fn difference(items: List(a), excluded: List(a)) -> List(a) {
  do_difference(items, excluded, [])
}

fn do_difference(items, excluded, accumulator) {
  case items {
    [] -> list.reverse(accumulator)
    [next, ..items] ->
      case list.find(excluded, fn(n) { n == next }) {
        Ok(_) -> do_difference(items, excluded, accumulator)
        Error(_) -> push_new(next, accumulator)
      }
  }
}

fn do_used_in_type(set, type_) {
  case type_ {
    Unbound(i) -> push_new(i, set)
    Native(_) | Binary -> set
    Tuple(elements) -> list.fold(elements, set, do_used_in_type)
    Record(rows, rest) | Union(rows, rest) -> do_used_in_row(rows, rest, set)
    Recursive(i, type_) -> {
      let set = push_new(i, set)
      do_used_in_type(set, type_)
    }
    Function(from, to) -> {
      let set = do_used_in_type(set, from)
      do_used_in_type(set, to)
    }
  }
}

fn do_used_in_row(rows, rest, set) {
  let set =
    list.fold(
      rows,
      set,
      fn(set, row) {
        let #(_name, type_) = row
        do_used_in_type(set, type_)
      },
    )
  case rest {
    None -> set
    // Already resolved
    Some(i) -> push_new(i, set)
  }
}

pub fn used_in_type(t) {
  do_used_in_type([], t)
}
