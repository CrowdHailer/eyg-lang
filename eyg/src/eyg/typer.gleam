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
  State(variables, 0, [], [], [])
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
fn match_pattern(pattern, given, typer) {
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
  Ok(#(#(name, type_), append_path(typer, 999)))
}

fn append_path(typer, i) {
  let State(location: location, ..) = typer
  State(..typer, location: list.append(location, [i]))
}

pub type Metadata {
  Metadata(
    path: List(Int),
    type_: Result(monotype.Monotype, Reason),
    scope: List(#(String, polytype.Polytype)),
  )
}

pub fn get_type(
  tree: ast.Expression(Metadata),
) -> Result(monotype.Monotype, Reason) {
  let #(Metadata(type_: type_, ..), _) = tree
  type_
}

pub fn infer(
  tree: ast.Expression(Nil),
  typer: State,
) -> Result(#(ast.Expression(Metadata), State), #(Reason, State)) {
  // return all context so more info can be added later
  let #(_, tree) = tree
  let State(location: path, ..) = typer
  // Todo use function that takes type into meta
  let meta = Metadata(path: path, type_: _, scope: typer.variables)
  case tree {
    Binary(value) ->
      Ok(#(
        #(
          Metadata(
            path: path,
            type_: Ok(monotype.Binary),
            scope: typer.variables,
          ),
          Binary(value),
        ),
        typer,
      ))
    Tuple(elements) -> {
      // infer_with_scope(s)
      // t can't be typer, compiler bug
      let State(location: path, ..) = typer
      try #(trees, #(typer, _)) =
        list.try_map_state(
          elements,
          #(typer, 0),
          fn(element, state) {
            let #(t, i) = state
            let p = list.append(path, [i])
            let t = State(..t, location: p)
            try #(type_, t) = infer(element, t)
            Ok(#(type_, #(t, i + 1)))
          },
        )
      // TODO type should always be ok that it's tuples
      let Ok(types) = list.try_map(trees, get_type)
      let type_ = monotype.Tuple(types)
      let metadata =
        Metadata(path: path, type_: Ok(type_), scope: typer.variables)
      Ok(#(#(metadata, Tuple(trees)), typer))
    }
    Row(fields) -> {
      try #(trees, typer) = list.try_map_state(fields, typer, infer_field)
      let types =
        list.map(
          trees,
          fn(tree_with_other_name) {
            let #(name, #(Metadata(type_: Ok(type_), ..), _)) =
              tree_with_other_name
            #(name, type_)
          },
        )
      let type_ = monotype.Row(types, None)
      let metadata =
        Metadata(path: path, type_: Ok(type_), scope: typer.variables)
      Ok(#(#(metadata, Row(trees)), typer))
    }

    Variable(label) ->
      case get_variable(label, typer) {
        Ok(#(type_, typer)) ->
          Ok(#(
            #(
              Metadata(path: path, type_: Ok(type_), scope: typer.variables),
              Variable(label),
            ),
            typer,
          ))
        Error(#(reason, _)) ->
          Ok(#(
            #(
              Metadata(path: path, type_: Error(reason), scope: typer.variables),
              Variable(label),
            ),
            typer,
          ))
      }
    Let(pattern, value, then) -> {
      let State(location: location, ..) = typer
      // TODO remove this nesting when we(if?) separate typer and scope
      let State(variables: variables, ..) = typer
      try #(value, typer) = infer(value, append_path(typer, 0))
      let #(given, typer) = case get_type(value) {
        Ok(given) -> #(given, typer)
        Error(_) -> {
          let #(x, typer) = polytype.next_unbound(typer)
          #(monotype.Unbound(x), typer)
        }
      }
      let typer = State(..typer, variables: variables)
      case match_pattern(pattern, given, typer) {
        Ok(typer) -> {
          // same rule as scope needs reseting
          let typer = State(..typer, location: location)
          try #(then, typer) = infer(then, append_path(typer, 1))
          let #(then_type, typer) = case get_type(then) {
            Ok(t) -> #(t, typer) 
            Error(_) -> {
              let #(x, typer) = polytype.next_unbound(typer)
              #(monotype.Unbound(x), typer)
            }
          }
          let metadata =
            Metadata(path: path, type_: Ok(then_type), scope: typer.variables)
          let tree = Let(pattern, value, then)
          Ok(#(#(metadata, tree), typer))
        }
        Error(#(reason, typer)) -> {
          // all the variables in the pattern should be added to scope
          let typer = State(..typer, location: location)
          try #(then, typer) = infer(then, append_path(typer, 1))
          let metadata =
            Metadata(path: path, type_: Error(reason), scope: typer.variables)
          let tree = Let(pattern, value, then)
          Ok(#(#(metadata, tree), typer))

        }
      }
    }
    Function(label, body) -> {
      let #(x, typer) = polytype.next_unbound(typer)
      let type_var = monotype.Unbound(x)
      // TODO remove this nesting when we(if?) separate typer and scope
      let State(variables: variables, location: location, ..) = typer
      let typer = set_variable(label, type_var, typer)
      try #(return, typer) = infer(body, append_path(typer, 0))
      let typer = State(..typer, variables: variables, location: location)
      // There are ALOT more type variables if handling all the errors.
      let Ok(return_type) = get_type(return)
      let type_ = monotype.Function(type_var, return_type)
      let metadata =
        Metadata(path: path, type_: Ok(type_), scope: typer.variables)
      Ok(#(#(metadata, Function(label, return)), typer))
    }
    Call(function, with) -> {
      let State(location: location, ..) = typer
      try #(function, typer) = infer(function, append_path(typer, 0))
      let typer = State(..typer, location: location)
      try #(with, typer) = infer(with, append_path(typer, 1))
      let typer = State(..typer, location: location)
      let #(x, typer) = polytype.next_unbound(typer)
      let return_type = monotype.Unbound(x)
      let Ok(ftype) = get_type(function)
      // TODO unify error should always work
      let Ok(with_type) = get_type(with)
      case unify(ftype, monotype.Function(with_type, return_type), typer) {
        Ok(typer) -> {
          let metadata =
            Metadata(path: path, type_: Ok(return_type), scope: typer.variables)
          Ok(#(#(metadata, Call(function, with)), typer))
        }
        Error(#(reason, typer)) -> {
          let metadata =
            Metadata(path: path, type_: Error(reason), scope: typer.variables)
          Ok(#(#(metadata, Call(function, with)), typer))
        }

      }
    }
    Name(new_type, then) -> {
      let #(named, _construction) = new_type
      let State(nominal: nominal, ..) = typer
      case list.key_find(nominal, named) {
        Error(Nil) -> {
          let typer = State(..typer, nominal: [new_type, ..nominal])
          try #(then, typer) = infer(then, append_path(typer, 0))
          let metadata =
            Metadata(path: path, type_: get_type(then), scope: typer.variables)
          let tree = Name(new_type, then)
          Ok(#(#(metadata, tree), typer))
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
              let metadata =
                Metadata(
                  path: path,
                  type_: Ok(monotype),
                  scope: typer.variables,
                )
              Ok(#(#(metadata, Constructor(named, variant)), typer))
            }
            Error(Nil) -> Error(#(UnknownVariant(variant, named), typer))
          }
        Error(Nil) -> Error(#(UnknownType(named), typer))
      }
    }
    Case(named, subject, clauses) -> {
      let State(nominal: nominal, location: location, ..) = typer
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
          try #(subject, typer) = infer(subject, typer)
          // Maybe this unify should be typed at the location of the whole case
          let Ok(subject_type) = get_type(subject)
          try typer = unify(expected, subject_type, typer)
          let #(x, typer) = polytype.next_unbound(typer)
          let return_type = monotype.Unbound(x)
          let State(variables: variables, ..) = typer
          try #(clauses, #(unhandled, typer)) =
            list.try_map_state(
              clauses,
              #(variants, typer),
              // This is an error caused when the name typer is used.
              fn(clause, state) { // Step on earlier because 0 index is subject
                // let typer = step_on_location(typer)
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
                try #(then, t) = infer(then, t)
                let clause = #(variant, variable, then)
                let Ok(then_type) = get_type(then)
                try t = unify(return_type, then_type, t)
                Ok(#(clause, #(remaining, t))) },
            )
          case unhandled {
            [] -> {
              let metadata =
                Metadata(
                  path: path,
                  type_: Ok(return_type),
                  scope: typer.variables,
                )
              let tree = Case(named, subject, clauses)
              Ok(#(#(metadata, tree), typer))
            }
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
    Provider(id, generator) -> {
      let type_ = monotype.Unbound(id)
      let metadata =
        Metadata(path: path, type_: Ok(type_), scope: typer.variables)
      Ok(#(#(metadata, Provider(id, generator)), typer))
    }
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
