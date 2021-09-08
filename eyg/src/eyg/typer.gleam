import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg/ast
import eyg/ast/expression.{
  Binary, Call, Case, Constructor, Function, Let, Name, Provider, Row, Tuple, Variable, Expression
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
  UnexpectedFields(expected: List(#(String, monotype.Monotype)))
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
        only, None -> Error(#(UnexpectedFields(only), typer))
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

fn set_variable(variable, state) {
  let #(label, monotype) = variable
  let State(variables: variables, substitutions: substitutions, ..) = state
  let polytype =
    polytype.generalise(monotype.resolve(monotype, substitutions), state)
  let variables = [#(label, polytype), ..variables]
  State(..state, variables: variables, substitutions: substitutions)
}

fn pattern_type(pattern, typer) {
  case pattern {
    pattern.Variable(label) -> {
      let #(x, typer) = polytype.next_unbound(typer)
      let type_var = monotype.Unbound(x)
      #(type_var, [#(label, type_var)], typer)
    }
    pattern.Tuple(elements) -> {
      let #(elements, typer) = list.map_state(elements, typer, with_unbound)
      let expected = monotype.Tuple(list.map(elements, pairs_second))
      #(expected, elements, typer)
    }
    pattern.Row(fields) -> {
      let #(fields, typer) = list.map_state(fields, typer, with_unbound)
      let extract_field_types = fn(named_field) {
        let #(#(name, _assignment), type_) = named_field
        #(name, type_)
      }
      let #(x, typer) = polytype.next_unbound(typer)
      let expected =
        monotype.Row(list.map(fields, extract_field_types), Some(x))
      let extract_scope_variables = fn(x) {
        let #(#(_name, assignment), type_) = x
        #(assignment, type_)
      }
      let variables = list.map(fields, extract_scope_variables)
      #(expected, variables, typer)
    }
  }
}

// inference fns
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
  tree: Expression(Metadata),
) -> Result(monotype.Monotype, Reason) {
  let #(Metadata(type_: type_, ..), _) = tree
  type_
}

fn do_unify(expected, given, typer) {
  case unify(expected, given, typer) {
    Ok(typer) -> #(Ok(expected), typer)
    // Don't think typer needs returning from unify?
    Error(#(reason, typer)) -> #(Error(reason), typer)
  }
}

fn pairs_first(pair: #(a, b)) -> a {
  pair.0
}

fn pairs_second(pair: #(a, b)) -> b {
  pair.1
}

fn with_unbound(thing: a, typer) -> #(#(a, monotype.Monotype), State) {
  let #(x, typer) = polytype.next_unbound(typer)
  let type_ = monotype.Unbound(x)
  #(#(thing, type_), typer)
}

pub fn infer_unconstrained(expression) {
  let typer = init([])
  let #(x, typer) = polytype.next_unbound(typer)
  let expected = monotype.Unbound(x)
  infer(expression, expected, typer)
}

pub fn infer(
  expression: Expression(Nil),
  expected: monotype.Monotype,
  typer: State,
) -> #(Expression(Metadata), State) {
  // return all context so more info can be added later
  let #(_, tree) = expression
  let State(location: path, ..) = typer
  let meta = Metadata(path: path, type_: _, scope: typer.variables)
  case tree {
    Binary(value) -> {
      let #(type_, typer) = do_unify(expected, monotype.Binary, typer)
      let expression = #(meta(type_), Binary(value))
      #(expression, typer)
    }
    Tuple(elements) -> {
      let #(pairs, typer) = list.map_state(elements, typer, with_unbound)
      let given = monotype.Tuple(list.map(pairs, pairs_second))
      let #(type_, typer) = do_unify(expected, given, typer)
      // decided I want to match on top level first
      let #(elements, #(typer, _)) =
        list.map_state(
          pairs,
          #(typer, 0),
          fn(pair, stz) {
            let #(tz, i) = stz
            let #(element, expected) = pair
            let tz = State(..tz, location: ast.append_path(path, i))
            let #(element, tz) = infer(element, expected, tz)
            #(element, #(tz, i + 1))
          },
        )
      let expression = #(meta(type_), Tuple(elements))
      #(expression, typer)
    }
    Row(fields) -> {
      let #(pairs, typer) = list.map_state(fields, typer, with_unbound)
      let given =
        monotype.Row(
          list.map(
            pairs,
            fn(pair) {
              let #(#(name, _value), type_) = pair
              #(name, type_)
            },
          ),
          None,
        )
      // TODO don't think returning type_ needed
      let #(type_, typer) = do_unify(expected, given, typer)
      let #(fields, #(typer, _)) =
        list.map_state(
          pairs,
          #(typer, 0),
          fn(pair, stz) {
            let #(tz, i) = stz
            let #(#(name, value), expected) = pair
            let tz = State(..tz, location: ast.append_path(path, i))
            let #(value, tz) = infer(value, expected, tz)
            #(#(name, value), #(tz, i + 1))
          },
        )
      let expression = #(meta(type_), Row(fields))
      #(expression, typer)
    }
    Variable(label) -> {
      // Returns typer because of instantiation, 
      let #(type_, typer) = case get_variable(label, typer) {
        Ok(#(given, typer)) -> do_unify(expected, given, typer)
        Error(#(reason, _)) -> #(Error(reason), typer)
      }
      let expression = #(meta(type_), Variable(label))
      #(expression, typer)
    }
    Let(pattern, value, then) -> {
      let State(variables: variables, location: location, ..) = typer
      let #(expected_value, bound_variables, typer) =
        pattern_type(pattern, typer)
      // TODO remove this nesting when we(if?) separate typer and scope
      let #(value, typer) = infer(value, expected_value, append_path(typer, 0))
      let typer = State(..typer, variables: variables, location: location)
      let typer = list.fold(bound_variables, typer, set_variable)
      let #(then, typer) = infer(then, expected, append_path(typer, 1))
      // Let is always OK the error is on the term inside
      let expression = #(meta(Ok(expected)), Let(pattern, value, then))
      #(expression, typer)
    }
    Function(label, body) -> {
      let #(x, typer) = polytype.next_unbound(typer)
      let arg_type = monotype.Unbound(x)
      let #(y, typer) = polytype.next_unbound(typer)
      let return_type = monotype.Unbound(y)
      let given = monotype.Function(arg_type, return_type)
      let #(type_, typer) = do_unify(expected, given, typer)
      // TODO remove this nesting when we(if?) separate typer and scope
      let State(variables: variables, location: location, ..) = typer
      let typer = set_variable(#(label, arg_type), typer)
      let #(return, typer) = infer(body, return_type, append_path(typer, 0))
      let typer = State(..typer, variables: variables, location: location)
      // There are ALOT more type variables if handling all the errors.
      #(#(meta(type_), Function(label, return)), typer)
    }
    Call(function, with) -> {
      let State(location: location, ..) = typer
      let #(x, typer) = polytype.next_unbound(typer)
      let arg_type = monotype.Unbound(x)
      let expected_function = monotype.Function(arg_type, expected)
      let #(function, typer) =
        infer(function, expected_function, append_path(typer, 0))
      let typer = State(..typer, location: location)
      let #(with, typer) = infer(with, arg_type, append_path(typer, 1))
      let typer = State(..typer, location: location)
      // Type is always! OK at this level
      let expression = #(meta(Ok(expected)), Call(function, with))
      #(expression, typer)
    }
    Name(new_type, then) -> {
      let #(named, _construction) = new_type
      let State(nominal: nominal, ..) = typer
      let #(add_name, typer) = case list.key_find(nominal, named) {
        Error(Nil) -> {
          let typer = State(..typer, nominal: [new_type, ..nominal])
          #(Ok(Nil), typer)
        }
        Ok(_) -> #(Error(DuplicateType(named)), typer)
      }
      let #(then, typer) = infer(then, expected, append_path(typer, 0))
      let tree = Name(new_type, then)
      let type_ = case add_name {
        Ok(Nil) -> Ok(expected)
        Error(reason) -> Error(reason)
      }
      #(#(meta(type_), tree), typer)
    }
    Constructor(named, variant) -> {
      let State(nominal: nominal, ..) = typer
      let #(type_, typer) = case list.key_find(nominal, named) {
        Error(Nil) -> #(Error(UnknownType(named)), typer)
        Ok(#(parameters, variants)) ->
          case list.key_find(variants, variant) {
            Error(Nil) -> #(Error(UnknownVariant(variant, named)), typer)
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
              let #(given, typer) = polytype.instantiate(polytype, typer)
              do_unify(expected, given, typer)
            }
          }
      }
      let expression = #(meta(type_), Constructor(named, variant))
      #(expression, typer)
    }
    Case(named, subject, clauses) -> {
      let State(nominal: nominal, ..) = typer
      let #(expected_subject, typer, variants) = case list.key_find(
        nominal,
        named,
      ) {
        Error(Nil) -> #(Error(UnknownType(named)), typer, [])
        Ok(#(parameters, variants)) -> {
          let #(replacements, typer) =
            list.map_state(
              parameters,
              typer,
              fn(p, t) {
                let #(x, t) = polytype.next_unbound(t)
                #(#(p, x), t)
              },
            )
          let expected_subject =
            monotype.Nominal(named, list.map(parameters, monotype.Unbound))
            |> pair_replace(replacements, _)
          let variants =
            list.map(
              variants,
              fn(variant) {
                let #(name, type_) = variant
                #(name, pair_replace(replacements, type_))
              },
            )
          #(Ok(expected_subject), typer, variants)
        }
      }
      let State(location: location, variables: variables, ..) = typer
      let #(stype, typer) = case expected_subject {
        Ok(type_) -> #(type_, typer)
        Error(_) -> {
          let #(x, typer) = polytype.next_unbound(typer)
          let type_ = monotype.Unbound(x)
          #(type_, typer)
        }
      }
      let #(subject, typer) = infer(subject, stype, typer)
      let #(clauses, #(unhandled, typer)) =
        list.map_state(
          clauses,
          #(variants, typer),
          fn(clause, s) {
            let #(remaining, t) = s
            let #(variant, variable, then) = clause
            // TODO append path with i, are we even using the path if metdata local?
            let t = State(..t, location: location, variables: variables)
            case list.key_pop(remaining, variant) {
              Ok(#(type_, remaining)) -> {
                let t = set_variable(#(variable, type_), t)
                let #(then, t) = infer(then, expected, t)
                let clause = #(variant, variable, then)
                #(clause, #(remaining, t))
              }
              // If I want to show for several branches I need to store multi errors, cant to that on metadata a is.
              Error(_) -> {
                let #(x, t) = polytype.next_unbound(t)
                let type_ = monotype.Unbound(x)
                let #(then, t) = infer(then, expected, t)
                let #(metadata, tree) = then
                let metadata =
                  Metadata(
                    ..metadata,
                    type_: case list.key_find(variants, variant) {
                      Error(_) -> Error(UnknownVariant(variant, named))
                      Ok(_) -> Error(RedundantClause(variant))
                    },
                  )
                let then = #(metadata, tree)
                let clause = #(variant, variable, then)
                #(clause, #(remaining, t))
              }
            }
          },
        )
      let tree = Case(named, subject, clauses)
      let type_ = case expected_subject {
        Error(reason) -> Error(reason)
        Ok(_) ->
          case unhandled {
            // The errors in subject type in to be presented BUT if no error return expected tye
            [] -> Ok(expected)
            _ -> Error(UnhandledVariants(list.map(unhandled, pairs_first)))
          }
      }
      #(#(meta(type_), tree), typer)
    }
    Provider(generator) -> {
      let expression = #(meta(Ok(expected)), Provider(generator))
      #(expression, typer)
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
