import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg/ast.{Binary, Call, Constructor, Function, Let, Row, Tuple, Variable}
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
  MissingFields(expected: List(#(String, monotype.Monotype)))
  UnknownType(name: String)
  UnknownVariant(variant: String, in: String)
}

// UnhandledVarients(remaining: List(String))
// RedundantClause(match: String)
pub fn init(variables) {
  State(variables, 0, [])
}

fn next_unbound(state) {
  let State(next_unbound: i, ..) = state
  let state = State(..state, next_unbound: i + 1)
  #(i, state)
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
    monotype.Tuple(elements) -> {
      let elements = list.map(elements, resolve(_, typer))
      monotype.Tuple(elements)
    }
    monotype.Row(fields, rest) -> {
      let resolved_fields =
        list.map(
          fields,
          fn(field) {
            let #(name, type_) = field
            #(name, resolve(type_, typer))
          },
        )
      case rest {
        None -> monotype.Row(resolved_fields, None)
        Some(i) ->
          case resolve(monotype.Unbound(i), typer) {
            monotype.Unbound(j) -> monotype.Row(resolved_fields, Some(j))
            monotype.Row(inner, rest) ->
              monotype.Row(list.append(resolved_fields, inner), rest)
          }
      }
    }
    monotype.Function(from, to) -> {
      let from = resolve(from, typer)
      let to = resolve(to, typer)
      monotype.Function(from, to)
    }
    monotype.Nominal(name, parameters) ->
      monotype.Nominal(name, list.map(parameters, resolve(_, typer)))
  }
}

fn unify_pair(pair, typer) {
  let #(expected, given) = pair
  unify(expected, given, typer)
}

// monotype function??
fn unify(expected, given, typer) {
  let expected = resolve(expected, typer)
  let given = resolve(given, typer)
  case expected, given {
    monotype.Binary, monotype.Binary -> Ok(typer)
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
    monotype.Row(expected, expected_extra), monotype.Row(given, given_extra) -> {
      let #(expected, given, shared) = group_shared(expected, given)
      let #(x, typer) = next_unbound(typer)
      try typer = case given, expected_extra {
        [], _ -> Ok(typer)
        only, Some(i) -> {
          // TODO add substitution fn, could check i not been in subsitution before.
          let State(substitutions: substitutions, ..) = typer
          let substitutions = [
            #(i, monotype.Row(only, Some(x))),
            ..substitutions
          ]
          Ok(State(..typer, substitutions: substitutions))
        }
        only, None -> Error(MissingFields(only))
      }
      try typer = case expected, given_extra {
        [], _ -> Ok(typer)
        only, Some(i) -> {
          let State(substitutions: substitutions, ..) = typer
          let substitutions = [
            #(i, monotype.Row(only, Some(x))),
            ..substitutions
          ]
          Ok(State(..typer, substitutions: substitutions))
        }
        only, None -> Error(MissingFields(only))
      }
      list.try_fold(shared, typer, unify_pair)
    }
    monotype.Function(expected_from, expected_return), monotype.Function(
      given_from,
      given_return,
    ) -> {
      try typer = unify(expected_from, given_from, typer)
      unify(expected_return, given_return, typer)
    }
    expected, given -> Error(UnmatchedTypes(expected, given))
  }
}

fn group_shared(left, right) {
  do_group_shared(left, right, [], [])
}

fn do_group_shared(left, right, only_left, shared) {
  case left {
    [] -> #(list.reverse(only_left), right, list.reverse(shared))
    [#(k, left_value), ..left] ->
      case list.key_pop(right, k) {
        Ok(#(right_value, right)) -> {
          let shared = [#(left_value, right_value), ..shared]
          do_group_shared(left, right, only_left, shared)
        }
        Error(Nil) -> {
          let only_left = [#(k, left_value), ..only_left]
          do_group_shared(left, right, only_left, shared)
        }
      }
  }
}

// scope functions
fn get_variable(label, state) {
  let State(variables: variables, ..) = state
  case list.key_find(variables, label) {
    Ok(polytype) -> Ok(polytype.instantiate(polytype, state))
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
            let #(x, typer) = next_unbound(typer)
            let type_var = monotype.Unbound(x)
            let typer = set_variable(label, type_var, typer)
            #(type_var, typer)
          },
        )
      let expected = monotype.Tuple(types)
      unify(expected, given, typer)
    }
    pattern.Row(fields) -> {
      let #(typed_fields, typer) =
        list.map_state(
          fields,
          typer,
          fn(field, typer) {
            let #(name, label) = field
            let #(x, typer) = next_unbound(typer)
            let type_var = monotype.Unbound(x)
            let typer = set_variable(label, type_var, typer)
            #(#(name, type_var), typer)
          },
        )
      let #(x, typer) = next_unbound(typer)
      let expected = monotype.Row(typed_fields, Some(x))
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

pub fn nominal() {
  [
    #(
      "Boolean",
      #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
    ),
    #(
      "Option",
      #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
    ),
  ]
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
      Ok(#(monotype.Row(types, None), typer))
    }
    Constructor(named, variant) ->
      case list.key_find(nominal(), named) {
        Ok(#(parameters, variants)) ->
          case list.key_find(variants, variant) {
            Ok(argument) -> {
              let p =
                polytype.Polytype(
                  parameters,
                  monotype.Function(
                    argument,
                    monotype.Nominal(
                      named,
                      list.map(parameters, monotype.Unbound),
                    ),
                  ),
                )
              let m = polytype.instantiate(p, typer)
              Ok(#(m, typer))
            }
            Error(Nil) -> Error(UnknownVariant(variant, named))
          }
        Error(Nil) -> Error(UnknownType(named))
      }
    Variable(label) -> {
      try type_ = get_variable(label, typer)
      Ok(#(type_, typer))
    }
    Let(pattern, value, then) -> {
      try typer = match_pattern(pattern, value, typer)
      infer(then, typer)
    }
    Function(label, body) -> {
      let #(x, typer) = next_unbound(typer)
      let type_var = monotype.Unbound(x)
      let typer = set_variable(label, type_var, typer)
      try #(return, typer) = infer(body, typer)
      Ok(#(monotype.Function(type_var, return), typer))
    }
    Call(function, with) -> {
      try #(function_type, typer) = infer(function, typer)
      try #(with_type, typer) = infer(with, typer)
      let #(x, typer) = next_unbound(typer)
      let return_type = monotype.Unbound(x)
      try typer =
        unify(function_type, monotype.Function(with_type, return_type), typer)
      Ok(#(return_type, typer))
    }
  }
}
