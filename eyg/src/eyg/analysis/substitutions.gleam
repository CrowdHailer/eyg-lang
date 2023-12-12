import gleam/list
import gleam/dict.{type Dict}
import eyg/analysis/typ as t

pub type Substitutions {
  Substitutions(
    terms: Dict(Int, t.Term),
    rows: Dict(Int, t.Row(t.Term)),
    effects: Dict(Int, t.Row(#(t.Term, t.Term))),
  )
}

pub fn none() {
  Substitutions(dict.new(), dict.new(), dict.new())
}

// Look like set singleton
pub fn term(var, term) {
  none()
  |> insert_term(var, term)
}

pub fn row(var, row) {
  none()
  |> insert_row(var, row)
}

pub fn effect(var, effect) {
  none()
  |> insert_effect(var, effect)
}

pub fn insert_term(sub, var, term) {
  let Substitutions(terms, rows, effects) = sub
  Substitutions(dict.insert(terms, var, term), rows, effects)
}

pub fn insert_row(sub, var, row) {
  let Substitutions(terms, rows, effects) = sub
  Substitutions(terms, dict.insert(rows, var, row), effects)
}

pub fn insert_effect(sub, var, effect) {
  let Substitutions(terms, rows, effects) = sub
  Substitutions(terms, rows, dict.insert(effects, var, effect))
}

pub fn compose(sub1: Substitutions, sub2: Substitutions) {
  let terms =
    dict.merge(
      dict.map_values(sub2.terms, fn(_k, v) { apply(sub1, v) }),
      sub1.terms,
    )
  let rows =
    dict.merge(
      dict.map_values(sub2.rows, fn(_k, v) { apply_row(sub1, v) }),
      sub1.rows,
    )
  let effects =
    dict.merge(
      dict.map_values(sub2.effects, fn(_k, v) { apply_effects(sub1, v) }),
      sub1.effects,
    )
  Substitutions(terms, rows, effects)
}

pub fn drop(sub: Substitutions, vars) {
  list.fold(vars, sub, fn(sub, var) {
    let Substitutions(terms, rows, effects) = sub
    case var {
      t.Term(x) -> Substitutions(dict.drop(terms, [x]), rows, effects)
      t.Row(x) -> Substitutions(terms, dict.drop(rows, [x]), effects)
      t.Effect(x) -> Substitutions(terms, rows, dict.drop(effects, [x]))
    }
  })
}

pub fn apply(sub: Substitutions, typ) {
  case typ {
    t.Unbound(x) ->
      case dict.get(sub.terms, x) {
        Ok(replace) -> replace
        Error(Nil) -> typ
      }
    t.Fun(from, effects, to) ->
      t.Fun(apply(sub, from), apply_effects(sub, effects), apply(sub, to))
    t.Record(row) -> t.Record(apply_row(sub, row))
    t.Union(row) -> t.Union(apply_row(sub, row))
    t.Binary | t.Integer | t.Str -> typ
    t.LinkedList(element) -> t.LinkedList(apply(sub, element))
  }
}

pub fn apply_row(sub: Substitutions, row) {
  case row {
    t.Closed -> t.Closed
    t.Open(x) ->
      case dict.get(sub.rows, x) {
        Ok(replace) -> replace
        Error(Nil) -> row
      }
    t.Extend(label, value, tail) ->
      t.Extend(label, apply(sub, value), apply_row(sub, tail))
  }
}

pub fn apply_effects(sub: Substitutions, effect) {
  case effect {
    t.Closed -> t.Closed
    t.Open(x) ->
      case dict.get(sub.effects, x) {
        Ok(replace) -> replace
        Error(Nil) -> effect
      }
    t.Extend(label, #(in, out), tail) ->
      t.Extend(
        label,
        #(apply(sub, in), apply(sub, out)),
        apply_effects(sub, tail),
      )
  }
}
