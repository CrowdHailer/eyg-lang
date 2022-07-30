import gleam/io
import gleam/option.{None, Some}
import gleam/list
import eyg/typer/monotype as t

pub type Polytype {
  Polytype(forall: List(Int), monotype: t.Monotype)
}

// take in an i for the offset
// is there a name for the unification/constraints
pub fn instantiate(polytype, next_unbound) {
  let Polytype(forall, monotype) = polytype
  do_instantiate(forall, monotype, next_unbound)
}

fn do_instantiate(forall, monotype, next_unbound) {
  case forall {
    [] -> #(monotype, next_unbound)
    [variable, ..forall] -> {
      let monotype = replace_variable(monotype, variable, next_unbound)
      do_instantiate(forall, monotype, next_unbound + 1)
    }
  }
}

pub fn replace_variable(monotype, x, y) {
  case monotype {
    t.Native(name, inner) -> t.Native(name, list.map(inner, replace_variable(_, x, y)))
    t.Binary -> t.Binary
    t.Tuple(elements) -> t.Tuple(list.map(elements, replace_variable(_, x, y)))
    t.Record(fields, rest) -> {
      let fields =
        list.map(
          fields,
          fn(field) {
            let #(name, value) = field
            #(name, replace_variable(value, x, y))
          },
        )
      let rest = case rest {
        Some(i) if i == x -> Some(y)
        _ -> rest
      }
      t.Record(fields, rest)
    }
    t.Union(variants, rest) -> {
      let variants =
        list.map(
          variants,
          fn(variant) {
            let #(name, value) = variant
            #(name, replace_variable(value, x, y))
          },
        )
      let rest = case rest {
        Some(i) if i == x -> Some(y)
        _ -> rest
      }
      t.Union(variants, rest)
    }
    t.Function(from, to) ->
      t.Function(replace_variable(from, x, y), replace_variable(to, x, y))
    t.Unbound(i) ->
      case i == x {
        True -> t.Unbound(y)
        False -> t.Unbound(i)
      }
    t.Recursive(i, inner) -> {
      let i = case i == x {
        True -> y
        False -> i
      }
      t.Recursive(i, replace_variable(inner, x, y))
    }
  }
}

pub fn replace_type(monotype, x, t) {
  case monotype {
    t.Native(name, inner) -> t.Native(name, list.map(inner, replace_type(_, x, t)))
    t.Binary -> t.Binary
    t.Tuple(elements) -> t.Tuple(list.map(elements, replace_type(_, x, t)))
    t.Record(fields, rest) -> {
      let fields =
        list.map(
          fields,
          fn(field) {
            let #(name, value) = field
            #(name, replace_type(value, x, t))
          },
        )
      let rest = case rest {
        Some(i) if i == x -> todo("can't replace row variable with type")
        _ -> rest
      }
      t.Record(fields, rest)
    }
    t.Union(variants, rest) -> {
      let variants =
        list.map(
          variants,
          fn(variant) {
            let #(name, value) = variant
            #(name, replace_type(value, x, t))
          },
        )
      let rest = case rest {
        Some(i) if i == x -> todo("can't replace row variable with type")
        _ -> rest
      }
      t.Union(variants, rest)
    }
    t.Function(from, to) ->
      t.Function(replace_type(from, x, t), replace_type(to, x, t))
    t.Unbound(i) ->
      case i == x {
        True -> t
        False -> t.Unbound(i)
      }
    t.Recursive(i, inner) -> {
      let i = case i == x {
        True -> todo("can't replace recursive with type")
        False -> i
      }
      t.Recursive(i, replace_type(inner, x, t))
    }
  }
}

// maybe scope builds atop polytype
// MUST BE resolved first
pub fn generalise(monotype, variables) {
  case monotype {
    t.Function(_from, _to) -> {
      let in_type = t.free_in_type(monotype)
      let in_scope = free_variables_in_scope(variables)
      Polytype(difference(in_type, in_scope), monotype)
    }
    _ -> Polytype([], monotype)
  }
}

fn free_variables_in_scope(variables) {
  list.fold(
    variables,
    [],
    fn(free, variable) {
      let #(_label, polytype) = variable
      free_variables_in_polytype(polytype)
      |> union(free)
    },
  )
}

fn free_variables_in_polytype(polytype) {
  let Polytype(quantified, monotype) = polytype
  t.free_in_type(monotype)
  |> difference(quantified)
}

fn difference(items: List(a), excluded: List(a)) -> List(a) {
  do_difference(items, excluded, [])
}

fn do_difference(items, excluded, accumulator) {
  case items {
    [] -> list.reverse(accumulator)
    [next, ..items] ->
      case list.find(excluded, fn(i) { i == next }) {
        Ok(_) -> do_difference(items, excluded, accumulator)
        Error(_) -> push_new(next, accumulator)
      }
  }
}

fn union(new: List(a), existing: List(a)) -> List(a) {
  case new {
    [] -> existing
    [next, ..new] -> {
      let existing = push_new(next, existing)
      union(new, existing)
    }
  }
}

fn push_new(item: a, set: List(a)) -> List(a) {
  case list.find(set, fn(i) { i == item }) {
    Ok(_) -> set
    Error(Nil) -> [item, ..set]
  }
}
