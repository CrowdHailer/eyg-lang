import gleam/dict
import gleam/list
import gleam/result.{try}

// isomorphic as the opposite of kinded, all types have the same kind.
// This is my terminology.
// Avoid calling simple, is there a more precise name

pub type Type(var) {
  Var(key: var)
  Fun(Type(var), Type(var), Type(var))
  Binary
  Integer
  String
  List(Type(var))
  Record(Type(var))
  Union(Type(var))
  Empty
  RowExtend(String, Type(var), Type(var))
  EffectExtend(String, #(Type(var), Type(var)), Type(var))
  Promise(Type(var))
}

pub fn vars(type_) {
  list.reverse(do_vars(type_, []))
}

fn do_vars(type_, acc) {
  case type_ {
    Var(x) ->
      case list.contains(acc, x) {
        True -> acc
        False -> [x, ..acc]
      }
    Fun(from, eff, to) -> {
      let acc = do_vars(from, acc)
      let acc = do_vars(eff, acc)
      let acc = do_vars(to, acc)
      acc
    }
    Binary | Integer | String -> acc
    List(inner) -> do_vars(inner, acc)
    Record(inner) -> do_vars(inner, acc)
    Union(inner) -> do_vars(inner, acc)
    Empty -> acc
    RowExtend(_label, field, rest) -> {
      let acc = do_vars(field, acc)
      let acc = do_vars(rest, acc)
      acc
    }
    EffectExtend(_label, #(lift, lower), rest) -> {
      let acc = do_vars(lift, acc)
      let acc = do_vars(lower, acc)
      let acc = do_vars(rest, acc)
      acc
    }
    Promise(inner) -> do_vars(inner, acc)
  }
}

pub fn substitute(type_, substitutions) {
  case type_ {
    Var(x) ->
      case dict.get(substitutions, x) {
        Ok(replacement) -> Ok(replacement)
        Error(Nil) -> Error(x)
      }
    Fun(from, eff, to) -> {
      use from <- try(substitute(from, substitutions))
      use eff <- try(substitute(eff, substitutions))
      use to <- try(substitute(to, substitutions))
      Ok(Fun(from, eff, to))
    }
    Binary -> Ok(Binary)
    Integer -> Ok(Integer)
    String -> Ok(String)
    List(inner) -> substitute(inner, substitutions) |> result.map(List)
    Record(inner) -> substitute(inner, substitutions) |> result.map(Record)
    Union(inner) -> substitute(inner, substitutions) |> result.map(Union)
    Empty -> Ok(Empty)
    RowExtend(label, field, rest) -> {
      use field <- try(substitute(field, substitutions))
      use rest <- try(substitute(rest, substitutions))
      Ok(RowExtend(label, field, rest))
    }
    EffectExtend(label, #(lift, lower), rest) -> {
      use lift <- try(substitute(lift, substitutions))
      use lower <- try(substitute(lower, substitutions))
      use rest <- try(substitute(rest, substitutions))
      Ok(EffectExtend(label, #(lift, lower), rest))
    }
    Promise(inner) -> substitute(inner, substitutions) |> result.map(Promise)
  }
}

pub const unit = Record(Empty)

pub const boolean = Union(
  RowExtend("True", unit, RowExtend("False", unit, Empty)),
)

pub fn rows(rows) {
  do_rows(rows, Empty)
}

pub fn do_rows(rows, tail) {
  list.fold(list.reverse(rows), tail, fn(tail, row) {
    let #(label, value) = row
    RowExtend(label, value, tail)
  })
}

pub fn record(fields) {
  Record(rows(fields))
}

pub fn union(fields) {
  Union(rows(fields))
}

pub fn result(value, reason) {
  Union(RowExtend("Ok", value, RowExtend("Error", reason, Empty)))
}

pub fn option(value) {
  Union(RowExtend("Some", value, RowExtend("None", unit, Empty)))
}

pub const file = Record(
  RowExtend("name", String, RowExtend("content", Binary, Empty)),
)

pub fn ast() {
  List(
    union([
      #("Variable", String),
      #("Lambda", String),
      #("Apply", unit),
      #("Let", String),
      #("Binary", Binary),
      #("Integer", Integer),
      #("String", String),
      #("Tail", unit),
      #("Cons", unit),
      #("Vacant", String),
      #("Empty", unit),
      #("Extend", String),
      #("Select", String),
      #("Overwrite", String),
      #("Tag", String),
      #("Case", String),
      #("NoCases", unit),
      #("Perform", String),
      #("Handle", String),
      #("Builtin", String),
    ]),
  )
}
