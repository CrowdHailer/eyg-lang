import gleam/option.{Some}
import gleam/list
import eyg/typer/monotype.{Binary, Function, Monotype, Row, Tuple, Unbound}

// TODO break up scope typer
pub type State {
  State(
    variables: List(#(String, Polytype)),
    next_unbound: Int,
    substitutions: List(#(Int, Monotype)),
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
    Function(from, to) ->
      Function(replace_variable(from, x, y), replace_variable(to, x, y))
    Unbound(i) ->
      case i == x {
        True -> Unbound(y)
        False -> Unbound(i)
      }
  }
}

pub fn generalise(monotype) {
  // TODO generalise fns
  Polytype([], monotype)
}
