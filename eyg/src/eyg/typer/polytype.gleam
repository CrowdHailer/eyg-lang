import gleam/io
import gleam/option.{None, Some}
import gleam/list
import eyg/typer/monotype.{
  Binary, Function, Monotype, Nominal, Row, Tuple, Unbound,
}

// TODO break up scope typer
pub type State {
  State(
    variables: List(#(String, Polytype)),
    next_unbound: Int,
    substitutions: List(#(Int, Monotype)),
    nominal: List(#(String, #(List(Int), List(#(String, monotype.Monotype))))),
  )
}

pub fn next_unbound(state) {
  let State(next_unbound: i, ..) = state
  let state = State(..state, next_unbound: i + 1)
  #(i, state)
}

pub type Polytype {
  Polytype(forall: List(Int), monotype: Monotype)
}

// take in an i for the offset
// is there a name for the unification/constraints
pub fn instantiate(polytype, typer) {
  let Polytype(forall, monotype) = polytype
  do_instantiate(forall, monotype, typer)
}

fn do_instantiate(forall, monotype, typer) {
  case forall {
    [] -> #(monotype, typer)
    [variable, ..forall] -> {
      let #(replacement, typer) = next_unbound(typer)
      let monotype = replace_variable(monotype, variable, replacement)
      do_instantiate(forall, monotype, typer)
    }
  }
}

fn replace_variable(monotype, x, y) {
  case monotype {
    Binary -> Binary
    Tuple(elements) -> Tuple(list.map(elements, replace_variable(_, x, y)))
    Row(fields, rest) -> {
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
      Row(fields, rest)
    }
    Nominal(name, elements) ->
      Nominal(name, list.map(elements, replace_variable(_, x, y)))
    Function(from, to) ->
      Function(replace_variable(from, x, y), replace_variable(to, x, y))
    Unbound(i) ->
      case i == x {
        True -> Unbound(y)
        False -> Unbound(i)
      }
  }
}

// maybe scope builds atop polytype
// MUST BE resolved first
pub fn generalise(monotype, state) {
  case monotype {
    Function(_from, _to) -> {
      let State(variables: variables, ..) = state
      let in_type = free_variables_in_monotype(monotype)
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
    fn(variable, free) {
      let #(_label, polytype) = variable
      free_variables_in_polytype(polytype)
      |> union(free)
    },
  )
}

fn free_variables_in_polytype(polytype) {
  let Polytype(quantified, monotype) = polytype
  free_variables_in_monotype(monotype)
  |> difference(quantified)
}

fn free_variables_in_monotype(monotype) {
  case monotype {
    Binary -> []
    Tuple(elements) ->
      list.fold(
        elements,
        [],
        fn(element, accumulator) {
          union(free_variables_in_monotype(element), accumulator)
        },
      )
    Row(fields, extra) -> {
      let in_fields =
        list.fold(
          fields,
          [],
          fn(field, accumulator) {
            let #(_name, value) = field
            union(free_variables_in_monotype(value), accumulator)
          },
        )
      case extra {
        Some(i) -> push_new(i, in_fields)
        None -> in_fields
      }
    }

    Function(from, to) ->
      union(free_variables_in_monotype(from), free_variables_in_monotype(to))
    Unbound(i) -> [i]
  }
}

fn difference(items: List(a), excluded: List(a)) -> List(a) {
  do_difference(items, excluded, [])
}

fn do_difference(items, excluded, accumulator) {
  case items {
    [] -> list.reverse(accumulator)
    [next, ..items] ->
      case list.find(excluded, next) {
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
  case list.find(set, item) {
    Ok(_) -> set
    Error(Nil) -> [item, ..set]
  }
}
