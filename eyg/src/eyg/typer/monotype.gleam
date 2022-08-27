import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string

// pub type Row {
//   Row(members: List(#(String, Monotype)), extra: Option(Int))
// }

pub type Monotype {
  Native(name: String, parameters: List(Monotype))
  Binary
  Tuple(elements: List(Monotype))
  Record(fields: List(#(String, Monotype)), extra: Option(Int))
  Union(variants: List(#(String, Monotype)), extra: Option(Int))
  Function(from: Monotype, to: Monotype, effects: Monotype)
  Unbound(i: Int)
  Recursive(i: Int, type_: Monotype)
}

pub const empty = Union([], None)
pub fn open(i)  {
  Union([], Some(i))
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
    Function(from, to, effects) ->
      // need to add effects
      string.concat(["new T.Function(", literal(from), ",", literal(to), ")"])
    Unbound(i) -> string.concat(["new T.Unbound(", int.to_string(i), ")"])
    Native(_, _) | Union(_, _) | Recursive(_, _) -> todo("ss literal")
  }
}


pub fn do_resolve(type_, substitutions: List(#(Int, Monotype)), recuring) {
  case type_ {
    Native(name, parameters) -> {
      let parameters = list.map(parameters, do_resolve(_, substitutions, recuring))
      Native(name,parameters)
      }
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
    Recursive(i, inner) -> {
      let inner = do_resolve(inner, substitutions, [i, ..recuring])
      Recursive(i, inner)
    }
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
            x -> todo("should never have matched")
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
              io.debug("bad resolution of a union")
              io.debug(i)
              Union(resolved_variants, None)
              }
          }
        }
      }
    }
    Function(from, to, effects) -> {
      let from = do_resolve(from, substitutions, recuring)
      let to = do_resolve(to, substitutions, recuring)
      let effects = do_resolve(effects , substitutions, recuring)
      Function(from, to, effects)
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
    Native(_, parameters) ->{
      list.fold(parameters, set, do_free_in_type)
      }
    Binary -> set
    Tuple(elements) -> list.fold(elements, set, do_free_in_type)
    Record(rows, rest) | Union(rows, rest) -> do_free_in_row(rows, rest, set)
    Recursive(i, type_) -> {
      let inner = do_free_in_type(set, type_)
      difference(inner, [i])
    }
    Function(from, to, effects) -> {
      let set = do_free_in_type(set, from)
      let set = do_free_in_type(set, to)
      do_free_in_type(set, effects)
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

// Set TODO move to set dir
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
    Native(_, inner) -> list.fold(inner, set, do_used_in_type)
    Binary -> set
    Tuple(elements) -> list.fold(elements, set, do_used_in_type)
    Record(rows, rest) | Union(rows, rest) -> do_used_in_row(rows, rest, set)
    Recursive(i, type_) -> {
      let set = push_new(i, set)
      do_used_in_type(set, type_)
    }
    Function(from, to, effects) -> {
      let set = do_used_in_type(set, from)
      let set = do_used_in_type(set, to)
      do_used_in_type(set, effects)
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
