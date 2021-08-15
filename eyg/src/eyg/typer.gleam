import gleam/io
import gleam/list
import eyg/ast.{Binary, Let, Row, Tuple, Variable}
import eyg/ast/pattern
import eyg/typer/monotype
import eyg/typer/polytype

// Context/typer
pub type State {
  State(
    variables: List(#(String, polytype.Polytype)),
    next_unbound: Int,
    substitutions: List(#(Int, monotype.Monotype)),
  )
}

pub type Reason {
  IncorrectArity(expected: Int, given: Int)
  UnknownVariable(label: String)
  UnmatchedTypes(expected: monotype.Monotype, given: monotype.Monotype)
}

// UnhandledVarients(remaining: List(String))
// RedundantClause(match: String)
pub fn init(variables) {
  State(variables, 0, [])
}

fn next_unbound(state) {
  let State(next_unbound: i, ..) = state
  let state = State(..state, next_unbound: i + 1)
  #(monotype.Unbound(i), state)
}

pub fn resolve(type_, typer) {
  let State(substitutions: substitutions, ..) = typer
  case type_ {
    monotype.Unbound(i) ->
      case list.key_find(substitutions, i) {
        Ok(monotype.Unbound(j)) if i == j -> type_
        Error(Nil) -> type_
        Ok(substitution) -> resolve(substitution, typer)
      }
    monotype.Binary -> monotype.Binary
  }
}

fn unify_pair(pair, typer) {
  let #(expected, given) = pair
  unify(expected, given, typer)
}

// monotype function??
fn unify(expected, given, typer) {
  // I wonder if lazily calling resolve is a problem for rows.
  // TODO resolve
  case expected, given {
    monotype.Tuple(expected), monotype.Tuple(given) ->
      case list.zip(expected, given) {
        Error(#(expected, given)) -> Error(IncorrectArity(expected, given))
        Ok(pairs) -> list.try_fold(pairs, typer, unify_pair)
      }
    monotype.Unbound(i), any -> {
      let State(substitutions: substitutions, ..) = typer
      let substitutions = [#(i, any), ..substitutions]
      Ok(State(..typer, substitutions: substitutions))
    }
    any, monotype.Unbound(i) -> {
      let State(substitutions: substitutions, ..) = typer
      let substitutions = [#(i, any), ..substitutions]
      Ok(State(..typer, substitutions: substitutions))
    }

    expected, given -> Error(UnmatchedTypes(expected, given))
  }
}

// scope functions
fn get_variable(label, state) {
  let State(variables: variables, ..) = state
  case list.key_find(variables, label) {
    Ok(polytype) -> Ok(polytype.instantiate(polytype))
    Error(Nil) -> Error(UnknownVariable(label))
  }
}

fn set_variable(label, monotype, state) {
  let polytype = polytype.generalise(monotype)
  let State(variables: variables, ..) = state
  let variables = [#(label, polytype), ..variables]
  State(..state, variables: variables)
}

// assignment/patterns
fn match_pattern(pattern, value, typer) {
  try #(given, typer) = infer(value, typer)
  case pattern {
    pattern.Variable(label) -> Ok(set_variable(label, given, typer))
    pattern.Tuple(elements) -> {
      let #(types, typer) =
        list.map_state(
          elements,
          typer,
          fn(label, typer) {
            let #(type_var, typer) = next_unbound(typer)
            let typer = set_variable(label, type_var, typer)
            #(type_var, typer)
          },
        )
      let expected = monotype.Tuple(types)
      unify(expected, given, typer)
    }
  }
}

// inference fns
fn infer_field(field, typer) {
  let #(name, tree) = field
  try #(type_, typer) = infer(tree, typer)
  Ok(#(#(name, type_), typer))
}

pub fn infer(
  tree: ast.Node,
  typer: State,
) -> Result(#(monotype.Monotype, State), Reason) {
  case tree {
    Binary(_) -> Ok(#(monotype.Binary, typer))
    Tuple(elements) -> {
      try #(types, typer) = list.try_map_state(elements, typer, infer)
      Ok(#(monotype.Tuple(types), typer))
    }
    Row(fields) -> {
      try #(types, typer) = list.try_map_state(fields, typer, infer_field)
      Ok(#(monotype.Row(types), typer))
    }
    Variable(label) -> {
      try type_ = get_variable(label, typer)
      Ok(#(type_, typer))
    }
    Let(pattern, value, then) -> {
      try typer = match_pattern(pattern, value, typer)
      infer(then, typer)
    }
  }
}
