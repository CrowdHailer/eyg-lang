import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import eyg/misc
import eyg/ast
import eyg/ast/path
import eyg/ast/expression.{
  Binary, Call, Expression, Function, Let, Provider, Row, Tuple, Variable,
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
}

pub fn root_scope(variables) {
  Scope(variables: variables, path: [])
}

pub type Scope {
  Scope(path: List(Int), variables: List(#(String, polytype.Polytype)))
}

pub fn child(scope, i) {
  let Scope(path: path, ..) = scope
  Scope(..scope, path: path.append(path, i))
}

// TODO put the self name in here
pub fn reason_to_string(reason) {
  case reason {
    IncorrectArity(expected, given) ->
      string.concat([
        "Incorrect Arity expected ",
        int.to_string(expected),
        " given ",
        int.to_string(given),
      ])
    UnknownVariable(label) -> string.concat(["Unknown variable: \"", label, "\""])
    UnmatchedTypes(expected, given) ->
      string.concat([
        "Unmatched types expected ",
        monotype.to_string(expected),
        " given ",
        monotype.to_string(given),
      ])
    MissingFields(expected) ->
      // TODO add type information
      [
        "Missing fields:",
        ..list.map(expected, fn(x: #(String, monotype.Monotype)) { x.0 })
        |> list.intersperse(", ")
      ]
      |> string.concat

    UnexpectedFields(expected) -> "unexpectedfields"
  }
}

pub fn init() {
  State(0, [], [])
}

fn add_substitution(variable, resolves, typer) {
  let State(substitutions: substitutions, ..) = typer
  let substitutions = [#(variable, resolves), ..substitutions]
  State(..typer, substitutions: substitutions)
}

fn occurs_in(a, b) {
  case a {
    monotype.Unbound(i) ->
      case do_occurs_in(i, b) {
        True -> // TODO this very doesn't work
          // todo("Foo")
          True
        False -> False
      }
    _ -> False
  }
}

fn do_occurs_in(i, b) {
  case b {
    monotype.Unbound(j) if i == j -> True
    monotype.Unbound(_) -> False
    monotype.Binary -> False
    monotype.Function(from, to) -> do_occurs_in(i, from) || do_occurs_in(i, to)
    monotype.Tuple(elements) -> list.any(elements, do_occurs_in(i, _))
    monotype.Row(fields, _) ->
      fields
      |> list.map(fn(x: #(String, monotype.Monotype)) { x.1 })
      |> list.any(do_occurs_in(i, _))
  }
}

// monotype function??
// This will need the checker/unification/constraints data structure as it uses subsitutions and updates the next var value
// next unbound inside mono can be integer and unbound(i) outside
pub fn unify(expected, given, state) {
  // Pass as tuple to make reduce functions easier to implement
  // scope path is not modified through unification
  let #(typer, scope): #(State, Scope) = state
  let State(substitutions: substitutions, ..) = typer
  let expected = monotype.resolve(expected, substitutions)
  let given = monotype.resolve(given, substitutions)

  case occurs_in(expected, given) || occurs_in(given, expected) {
    True -> Ok(typer)
    False ->
      case expected, given {
        monotype.Binary, monotype.Binary -> Ok(typer)
        monotype.Tuple(expected), monotype.Tuple(given) ->
          case list.strict_zip(expected, given) {
            Error(_) ->
              Error(#(IncorrectArity(list.length(expected), list.length(given)), typer))
            Ok(pairs) ->
              list.try_fold(
                pairs,
                typer,
                fn(typer, pair) {
                  let #(expected, given) = pair
                  unify(expected, given, #(typer, scope))
                },
              )
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
          list.try_fold(
            shared,
            typer,
            fn(typer, pair) {
              let #(expected, given) = pair
              unify(expected, given, #(typer, scope))
            },
          )
        }
        monotype.Function(expected_from, expected_return), monotype.Function(
          given_from,
          given_return,
        ) -> {
          try x = unify(expected_from, given_from, state)
          unify(expected_return, given_return, #(x, scope))
        }
        expected, given -> Error(#(UnmatchedTypes(expected, given), typer))
      }
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
fn get_variable(label, typer, scope) {
  let Scope(variables: variables, ..) = scope
  case list.key_find(variables, label) {
    Ok(polytype) -> Ok(polytype.instantiate(polytype, typer))
    Error(Nil) -> Error(#(UnknownVariable(label), typer))
  }
}

fn set_variable(variable, typer, scope) {
  let #(label, monotype) = variable
  let State(substitutions: substitutions, ..) = typer
  let Scope(variables: variables, ..) = scope
  let polytype =
    polytype.generalise(monotype.resolve(monotype, substitutions), variables)
  let variables = [#(label, polytype), ..variables]
  Scope(..scope, variables: variables)
}

// No generalization
// TODO rename do_set_variable
fn set_self_variable(variable, scope) {
  let #(label, monotype) = variable
  let Scope(variables: variables, ..) = scope
  let polytype = polytype.Polytype([], monotype)
  let variables = [#(label, polytype), ..variables]
  Scope(..scope, variables: variables)
}

fn do_set_variable(scope, variable) {
  let Scope(variables: variables, ..) = scope
  let variables = [variable, ..variables]
  Scope(..scope, variables: variables)
}

fn ones_with_real_keys(elements, done) {
  case elements {
    [] -> list.reverse(done)
    [#(None, _), ..rest] -> ones_with_real_keys(rest, done)
    [#(Some(label), monotype), ..rest] ->
      ones_with_real_keys(rest, [#(label, monotype), ..done])
  }
}

fn pattern_type(pattern, typer) {
  case pattern {
    pattern.Discard -> {
      let #(x, typer) = polytype.next_unbound(typer)
      let type_var = monotype.Unbound(x)
      #(type_var, [], typer)
    }
    pattern.Variable(label) -> {
      let #(x, typer) = polytype.next_unbound(typer)
      let type_var = monotype.Unbound(x)
      #(type_var, [#(label, type_var)], typer)
    }
    pattern.Tuple(elements) -> {
      let #(elements, typer) = misc.map_state(elements, typer, with_unbound)
      let expected = monotype.Tuple(list.map(elements, pairs_second))
      let elements = ones_with_real_keys(elements, [])
      #(expected, elements, typer)
    }
    pattern.Row(fields) -> {
      let #(fields, typer) = misc.map_state(fields, typer, with_unbound)
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

pub type Metadata {
  Metadata(
    type_: Result(monotype.Monotype, Reason),
    scope: List(#(String, polytype.Polytype)),
    path: List(Int),
  )
}

pub fn is_error(metadata) {
  case metadata {
    Metadata(type_: Error(_), ..) -> True
    _ -> False
  }
}

pub fn get_type(tree: Expression(Metadata)) -> Result(monotype.Monotype, Reason) {
  let #(Metadata(type_: type_, ..), _) = tree
  type_
}

fn do_unify(expected, given, state) {
  let #(typer, scope): #(State, Scope) = state
  case unify(expected, given, state) {
    Ok(typer) -> #(Ok(expected), typer)
    // Don't think typer needs returning from unify?
    Error(#(reason, typer)) -> {
      let State(inconsistencies: inconsistencies, ..) = typer
      let inconsistencies = [
        #(scope.path, reason_to_string(reason)),
        ..typer.inconsistencies
      ]
      let typer = State(..typer, inconsistencies: inconsistencies)
      #(Error(reason), typer)
    }
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

pub fn equal_fn() {
  polytype.Polytype(
    [1, 2],
    monotype.Function(
      monotype.Tuple([monotype.Unbound(1), monotype.Unbound(1)]),
      // TODO Should the be part of parameterisation don't think so as not part of equal getting initialised
      monotype.Function(
        monotype.Row(
          [
            #(
              "True",
              monotype.Function(monotype.Tuple([]), monotype.Unbound(2)),
            ),
            #(
              "False",
              monotype.Function(monotype.Tuple([]), monotype.Unbound(2)),
            ),
          ],
          None,
        ),
        monotype.Unbound(2),
      ),
    ),
  )
}

pub fn infer_unconstrained(expression) {
  let typer = init()
  let scope = Scope(variables: [#("equal", equal_fn())], path: path.root())
  let #(x, typer) = polytype.next_unbound(typer)
  let expected = monotype.Unbound(x)
  infer(expression, expected, #(typer, scope))
}

pub fn infer(
  expression: Expression(Nil),
  expected: monotype.Monotype,
  // TODO rename State Typer
  state: #(State, Scope),
) -> #(Expression(Metadata), State) {
  // return all context so more info can be added later
  let #(_, tree) = expression
  let #(typer, scope) = state
  let meta = Metadata(type_: _, scope: scope.variables, path: scope.path)
  case tree {
    Binary(value) -> {
      let #(type_, typer) = do_unify(expected, monotype.Binary, #(typer, scope))
      let expression = #(meta(type_), Binary(value))
      #(expression, typer)
    }
    Tuple(elements) -> {
      let #(pairs, typer) = misc.map_state(elements, typer, with_unbound)
      let given = monotype.Tuple(list.map(pairs, pairs_second))
      let #(type_, typer) = do_unify(expected, given, #(typer, scope))
      // decided I want to match on top level first
      let #(elements, #(typer, _)) =
        misc.map_state(
          pairs,
          #(typer, 0),
          fn(pair, stz) {
            let #(tz, i) = stz
            let #(element, expected) = pair
            let #(element, tz) =
              infer(element, expected, #(tz, child(scope, i)))
            #(element, #(tz, i + 1))
          },
        )
      let expression = #(meta(type_), Tuple(elements))
      #(expression, typer)
    }
    Row(fields) -> {
      let #(pairs, typer) = misc.map_state(fields, typer, with_unbound)
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
      let #(type_, typer) = do_unify(expected, given, #(typer, scope))
      let #(fields, #(typer, _)) =
        misc.map_state(
          pairs,
          #(typer, 0),
          fn(pair, stz) {
            let #(tz, i) = stz
            let #(#(name, value), expected) = pair
            // let tz = State(..tz, location: path.append(path, i))
            let #(value, tz) =
              infer(value, expected, #(tz, child(child(scope, i), 1)))
            #(#(name, value), #(tz, i + 1))
          },
        )
      let expression = #(meta(type_), Row(fields))
      #(expression, typer)
    }
    Variable(label) -> {
      // Returns typer because of instantiation,
      // TODO separate lookup for instantiate, good for let rec
      let #(type_, typer) = case get_variable(label, typer, scope) {
        Ok(#(given, typer)) -> do_unify(expected, given, #(typer, scope))
        Error(#(reason, _)) -> {
          let State(inconsistencies: inconsistencies, ..) = typer
          let inconsistencies = [
            #(scope.path, reason_to_string(reason)),
            ..typer.inconsistencies
          ]
          let typer = State(..typer, inconsistencies: inconsistencies)
          #(Error(reason), typer)
        }
      }
      let expression = #(meta(type_), Variable(label))
      #(expression, typer)
    }
    Let(pattern, value, then) -> {
      let #(value, state) = case pattern, value {
        pattern.Variable(label), #(_, Function(pattern, body)) -> {
          let #(arg_type, bound_variables, typer) = pattern_type(pattern, typer)
          let #(y, typer) = polytype.next_unbound(typer)
          let return_type = monotype.Unbound(y)
          let given = monotype.Function(arg_type, return_type)
          // expected is value of let here don't unify that
          // let #(type_, typer) = do_unify(expected, given, typer)
          let bound_variables =
            list.map(
              bound_variables,
              fn(bv) {
                let #(label, monotype) = bv
                let polytype =
                  polytype.generalise(
                    monotype.resolve(monotype, typer.substitutions),
                    scope.variables,
                  )
                #(label, polytype)
              },
            )
          let scope = list.fold(bound_variables, scope, do_set_variable)
          let scope = set_self_variable(#(label, given), scope)
          let #(return, typer) =
            infer(body, return_type, #(typer, child(child(scope, 1), 1)))
          // io.debug(given)
          // io.debug(monotype.resolve(given, typer.substitutions) == given)
          // let [#("f", x), .._] = typer.variables
          // io.debug(x.monotype)
          // // let True = x == given
          // io.debug(monotype.resolve(x.monotype, typer.substitutions))
          // io.debug("===========")
          // io.debug(monotype.resolve(given, typer.substitutions))
          // Set again after clearing out in the middle
          let scope = set_variable(#(label, given), typer, scope)
          // There are ALOT more type variables if handling all the errors.
          #(#(meta(Ok(given)), Function(pattern, return)), #(typer, scope))
        }
        _, _ -> {
          let #(expected_value, bound_variables, typer) =
            pattern_type(pattern, typer)
          let #(value, typer) =
            infer(value, expected_value, #(typer, child(scope, 1)))
          let bound_variables =
            list.map(
              bound_variables,
              fn(bv) {
                let #(label, monotype) = bv
                let polytype =
                  polytype.generalise(
                    monotype.resolve(monotype, typer.substitutions),
                    scope.variables,
                  )
                #(label, polytype)
              },
            )
          let scope = list.fold(bound_variables, scope, do_set_variable)
          #(value, #(typer, scope))
        }
      }
      let #(typer, scope) = state
      let scope = child(scope, 2)
      let #(then, typer) = infer(then, expected, #(typer, scope))
      // Let is always OK the error is on the term inside
      let expression = #(meta(Ok(expected)), Let(pattern, value, then))
      #(expression, typer)
    }
    Function(pattern, body) -> {
      let #(arg_type, bound_variables, typer) = pattern_type(pattern, typer)
      let #(y, typer) = polytype.next_unbound(typer)
      let return_type = monotype.Unbound(y)
      let given = monotype.Function(arg_type, return_type)
      let #(type_, typer) = do_unify(expected, given, #(typer, scope))
      let bound_variables =
        list.map(
          bound_variables,
          fn(bv) {
            let #(label, monotype) = bv
            let polytype =
              polytype.generalise(
                monotype.resolve(monotype, typer.substitutions),
                scope.variables,
              )
            #(label, polytype)
          },
        )
      let scope = list.fold(bound_variables, scope, do_set_variable)
      let #(return, typer) = infer(body, return_type, #(typer, child(scope, 1)))
      // There are ALOT more type variables if handling all the errors.
      #(#(meta(type_), Function(pattern, return)), typer)
    }
    Call(function, with) -> {
      let #(x, typer) = polytype.next_unbound(typer)
      let arg_type = monotype.Unbound(x)
      let expected_function = monotype.Function(arg_type, expected)
      let #(function, typer) =
        infer(function, expected_function, #(typer, child(scope, 0)))
      let #(with, typer) = infer(with, arg_type, #(typer, child(scope, 1)))
      // Type is always! OK at this level
      let expression = #(meta(Ok(expected)), Call(function, with))
      #(expression, typer)
    }
    Provider(config, generator) -> {
      let typer = case generator == ast.generate_hole {
        True ->
          State(
            ..typer,
            inconsistencies: [
              #(scope.path, "todo: implementation missing"),
              ..typer.inconsistencies
            ],
          )
        False -> typer
      }
      let expression = #(meta(Ok(expected)), Provider(config, generator))
      #(expression, typer)
    }
  }
}

fn pair_replace(replacements, monotype) {
  list.fold(
    replacements,
    monotype,
    fn(monotype, pair) {
      let #(x, y) = pair
      polytype.replace_variable(monotype, x, y)
    },
  )
}
