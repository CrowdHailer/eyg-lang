import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg/ast.{
  Binary, Call, Case, Constructor, Function, Let, Name, Provider, Row, Tuple, Variable,
}
import eyg/ast/pattern
import eyg/typer/monotype
import eyg/typer/polytype.{State}

// Context/typer
pub type Reason {
  IncorrectArity(expected: Int, given: Int)
  UnknownVariable(label: String)
  UnmatchedTypes(expected: monotype.Monotype, given: monotype.Monotype)
  MissingFields(expected: List(#(String, monotype.Monotype)))
  UnknownType(name: String)
  UnknownVariant(variant: String, in: String)
  DuplicateType(name: String)
  RedundantClause(match: String)
  UnhandledVariants(remaining: List(String))
}

pub fn init(variables) {
  State(variables, 0, [], [], [0])
}

fn add_substitution(variable, resolves, typer) {
  let State(substitutions: substitutions, ..) = typer
  let substitutions = [#(variable, resolves), ..substitutions]
  State(..typer, substitutions: substitutions)
}

fn unify_pair(pair, typer) {
  let #(expected, given) = pair
  unify(expected, given, typer)
}

// monotype function??
// This will need the checker/unification/constraints data structure as it uses subsitutions and updates the next var value
// next unbound inside mono can be integer and unbound(i) outside
pub fn unify(expected, given, typer) {
  let State(substitutions: substitutions, ..) = typer
  let expected = monotype.resolve(expected, substitutions)
  let given = monotype.resolve(given, substitutions)
  case expected, given {
    monotype.Binary, monotype.Binary -> Ok(typer)
    monotype.Tuple(expected), monotype.Tuple(given) ->
      case list.zip(expected, given) {
        Error(#(expected, given)) ->
          Error(#(IncorrectArity(expected, given), typer))
        Ok(pairs) -> list.try_fold(pairs, typer, unify_pair)
      }
    monotype.Unbound(i), any -> Ok(add_substitution(i, any, typer))
    any, monotype.Unbound(i) -> Ok(add_substitution(i, any, typer))
    monotype.Row(expected, expected_extra), monotype.Row(given, given_extra) -> {
      let #(expected, given, shared) = group_shared(expected, given)
      let #(x, typer) = polytype.next_unbound(typer)
      try typer = case given, expected_extra {
        [], _ -> Ok(typer)
        only, Some(i) ->
          Ok(add_substitution(i, monotype.Row(only, Some(x)), typer))
        only, None -> Error(#(MissingFields(only), typer))
      }
      try typer = case expected, given_extra {
        [], _ -> Ok(typer)
        only, Some(i) ->
          Ok(add_substitution(i, monotype.Row(only, Some(x)), typer))
        only, None -> Error(#(MissingFields(only), typer))
      }
      list.try_fold(shared, typer, unify_pair)
    }
    monotype.Nominal(expected_name, expected_parameters), monotype.Nominal(
      given_name,
      given_parameters,
    ) -> {
      try _ = case expected_name == given_name {
        True -> Ok(Nil)
        False -> Error(#(UnmatchedTypes(expected, given), typer))
      }
      case list.zip(expected_parameters, given_parameters) {
        Error(#(_expected, _given)) ->
          todo("I don't think we should ever fail here")
        Ok(pairs) -> list.try_fold(pairs, typer, unify_pair)
      }
    }
    monotype.Function(expected_from, expected_return), monotype.Function(
      given_from,
      given_return,
    ) -> {
      try typer = unify(expected_from, given_from, typer)
      unify(expected_return, given_return, typer)
    }
    expected, given -> Error(#(UnmatchedTypes(expected, given), typer))
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
    Error(Nil) -> Error(#(UnknownVariable(label), state))
  }
}

fn set_variable(label, monotype, state) {
  let State(variables: variables, substitutions: substitutions, ..) = state
  let polytype =
    polytype.generalise(monotype.resolve(monotype, substitutions), state)
  let variables = [#(label, polytype), ..variables]
  State(..state, variables: variables, substitutions: substitutions)
}

// assignment/patterns
fn match_pattern(pattern, value, typer) {
  // TODO remove this nesting when we(if?) separate typer and scope
  let State(variables: variables, ..) = typer
  try #(given, typer) = infer(value, typer)
  let typer = State(..typer, variables: variables)
  case pattern {
    pattern.Variable(label) -> Ok(set_variable(label, given, typer))
    pattern.Tuple(elements) -> {
      let #(types, typer) =
        list.map_state(
          elements,
          typer,
          // Don't call typer as there is a bug
          fn(label, t) {
            let #(x, t) = polytype.next_unbound(t)
            let type_var = monotype.Unbound(x)
            let t = set_variable(label, type_var, t)
            #(type_var, t)
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
          fn(field, t) {
            let #(name, label) = field
            let #(x, t) = polytype.next_unbound(t)
            let type_var = monotype.Unbound(x)
            let t = set_variable(label, type_var, t)
            #(#(name, type_var), t)
          },
        )
      let #(x, typer) = polytype.next_unbound(typer)
      let expected = monotype.Row(typed_fields, Some(x))
      unify(expected, given, typer)
    }
  }
}

// inference fns
fn infer_field(field, typer) {
  let #(name, tree) = field
  try #(type_, typer) = infer(tree, typer)
  // NOTE this assumes infer_field always used in a list.map context
  Ok(#(#(name, type_), step_on_location(typer)))
}

fn step_in_location(typer) {
  let State(location: location, ..) = typer
  State(..typer, location: list.append(location, [0]))
}

fn step_on_location(typer) {
  let State(location: location, ..) = typer
  let [current, ..rest] = list.reverse(location)
  let location = list.reverse([current + 1, ..rest])
  State(..typer, location: location)
}

pub fn infer(
  tree: ast.Expression(Nil),
  typer: State,
) -> Result(#(monotype.Monotype, State), #(Reason, State)) {
  // return all context so more info can be added later
  let #(Nil, tree) = tree
  case tree {
    Binary(_) -> Ok(#(monotype.Binary, typer))
    Tuple(elements) -> {
      // infer_with_scope(s)
      let typer = step_in_location(typer)
      // t can't be typer, compiler bug
      try #(types, typer) =
        list.try_map_state(
          elements,
          typer,
          fn(element, t) {
            try #(type_, t) = infer(element, t)
            let t = step_on_location(t)
            Ok(#(type_, t))
          },
        )
      Ok(#(monotype.Tuple(types), typer))
    }
    Row(fields) -> {
      let typer = step_in_location(typer)
      try #(types, typer) = list.try_map_state(fields, typer, infer_field)
      Ok(#(monotype.Row(types, None), typer))
    }
    Variable(label) -> {
      try #(type_, typer) = get_variable(label, typer)
      Ok(#(type_, typer))
    }
    Let(pattern, value, then) -> {
      let State(location: location, ..) = typer
      try typer = match_pattern(pattern, value, step_in_location(typer))
      // same rule as scope needs reseting
      let typer = step_on_location(State(..typer, location: location))
      infer(then, typer)
    }
    Function(label, body) -> {
      let #(x, typer) = polytype.next_unbound(typer)
      let type_var = monotype.Unbound(x)
      // TODO remove this nesting when we(if?) separate typer and scope
      let State(variables: variables, location: location, ..) = typer
      let typer = set_variable(label, type_var, typer)
      try #(return, typer) = infer(body, step_in_location(typer))
      let typer = State(..typer, variables: variables, location: location)
      Ok(#(monotype.Function(type_var, return), typer))
    }
    Call(function, with) -> {
      let State(location: location, ..) = typer
      try #(function_type, typer) = infer(function, step_in_location(typer))
      let typer = State(..typer, location: location)
      try #(with_type, typer) =
        infer(with, step_in_location(step_on_location(typer)))
      let typer = State(..typer, location: location)
      let #(x, typer) = polytype.next_unbound(typer)
      let return_type = monotype.Unbound(x)
      try typer =
        unify(function_type, monotype.Function(with_type, return_type), typer)
      Ok(#(return_type, typer))
    }
    Name(new_type, then) -> {
      // let typer = step_in_location(typer)
      let #(named, _construction) = new_type
      let State(nominal: nominal, ..) = typer
      case list.key_find(nominal, named) {
        Error(Nil) -> {
          let typer = State(..typer, nominal: [new_type, ..nominal])
          infer(then, step_on_location(typer))
        }
        Ok(_) -> Error(#(DuplicateType(named), typer))
      }
    }
    Constructor(named, variant) -> {
      let State(nominal: nominal, ..) = typer
      case list.key_find(nominal, named) {
        Ok(#(parameters, variants)) ->
          case list.key_find(variants, variant) {
            Ok(argument) -> {
              // The could be generated in the name phase
              let polytype =
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
              let #(monotype, typer) = polytype.instantiate(polytype, typer)
              Ok(#(monotype, typer))
            }
            Error(Nil) -> Error(#(UnknownVariant(variant, named), typer))
          }
        Error(Nil) -> Error(#(UnknownType(named), typer))
      }
    }
    Case(named, subject, clauses) -> {
      let State(nominal: nominal, location: location, ..) = typer
      io.debug(location)
      case list.key_find(nominal, named) {
        // Think the old version errored by instantiating everytime
        Ok(#(parameters, variants)) -> {
          let #(replacements, typer) =
            list.map_state(
              parameters,
              typer,
              fn(parameter, typer) {
                let #(replacement, typer) = polytype.next_unbound(typer)
                let pair = #(parameter, replacement)
                #(pair, typer)
              },
            )
          let expected =
            pair_replace(
              replacements,
              monotype.Nominal(named, list.map(parameters, monotype.Unbound)),
            )
          let State(location: location, ..) = typer
          let typer = step_in_location(typer)
          try #(subject_type, typer) = infer(subject, typer)
          // Maybe this unify should be typed at the location of the whole case
          try typer = unify(expected, subject_type, typer)
          let #(x, typer) = polytype.next_unbound(typer)
          let return_type = monotype.Unbound(x)
          let State(variables: variables, ..) = typer
          try #(unhandled, typer) =
            list.try_fold(
              clauses,
              #(variants, typer),
              // This is an error caused when the name typer is used.
              fn(clause, state) {
                // Step on earlier because 0 index is subject
                let typer = step_on_location(typer)
                let #(remaining, t) = state
                let #(variant, variable, then) = clause
                try #(argument, remaining) = case list.key_pop(
                  remaining,
                  variant,
                ) {
                  Ok(value) -> Ok(value)
                  Error(Nil) ->
                    case list.key_find(variants, variant) {
                      Ok(_) -> Error(#(RedundantClause(variant), typer))
                      Error(Nil) ->
                        Error(#(UnknownVariant(variant, named), typer))
                    }
                }
                let argument = pair_replace(replacements, argument)
                // reset scope variables
                let t = State(..t, variables: variables)
                let t = set_variable(variable, argument, t)
                try #(type_, t) = infer(then, t)
                try t = unify(return_type, type_, t)
                Ok(#(remaining, t))
              },
            )
          case unhandled {
            [] -> Ok(#(return_type, typer))
            _ ->
              Error(#(
                UnhandledVariants(list.map(
                  unhandled,
                  fn(variant) {
                    let #(variant, _) = variant
                    variant
                  },
                )),
                State(..typer, location: location),
              ))
          }
        }
        Error(Nil) -> Error(#(UnknownType(named), typer))
      }
    }
    // Can't call the generator here because we don't know what the type will resolve to yet.
    Provider(id, _generator) -> Ok(#(monotype.Unbound(id), typer))
  }
}

fn pair_replace(replacements, monotype) {
  list.fold(
    replacements,
    monotype,
    fn(pair, monotype) {
      let #(x, y) = pair
      polytype.replace_variable(monotype, x, y)
    },
  )
}
