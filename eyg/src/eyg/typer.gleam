import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import eyg/ast
import eyg/ast/path
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype as t
import eyg/typer/polytype
import harness/harness

pub type Reason {
  IncorrectArity(expected: Int, given: Int)
  UnknownVariable(label: String)
  UnmatchedTypes(expected: t.Monotype, given: t.Monotype)
  MissingFields(expected: List(#(String, t.Monotype)))
  UnexpectedFields(expected: List(#(String, t.Monotype)))
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

pub type Typer {
  Typer(
    next_unbound: Int,
    substitutions: List(#(Int, t.Monotype)),
    // CAN'T hold onto typer.Reason circular dependency
    inconsistencies: List(#(List(Int), String)),
  )
}

// TODO put the self name in here
pub fn reason_to_string(reason) {
  case reason {
    IncorrectArity(expected, given) ->
      string.join([
        "Incorrect Arity expected ",
        int.to_string(expected),
        " given ",
        int.to_string(given),
      ])
    UnknownVariable(label) -> string.join(["Unknown variable: \"", label, "\""])
    UnmatchedTypes(expected, given) ->
      string.join([
        "Unmatched types expected ",
        t.to_string(expected),
        " given ",
        t.to_string(given),
      ])
    MissingFields(expected) ->
      // TODO add type information
      [
        "Missing fields:",
        ..list.map(expected, fn(x: #(String, t.Monotype)) { x.0 })
        |> list.intersperse(", ")
      ]
      |> string.join

    UnexpectedFields(expected) -> "unexpectedfields"
  }
}

pub fn init() {
  Typer(0, [], [])
}

fn add_substitution(variable, resolves, typer) {
  let Typer(substitutions: substitutions, ..) = typer
  let substitutions = [#(variable, resolves), ..substitutions]
  Typer(..typer, substitutions: substitutions)
}

fn occurs_in(a, b) {
  case a {
    t.Unbound(i) ->
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
    t.Unbound(j) if i == j -> True
    t.Unbound(_) -> False
    t.Native(_) -> False
    t.Binary -> False
    t.Function(from, to) -> do_occurs_in(i, from) || do_occurs_in(i, to)
    t.Tuple(elements) -> list.any(elements, do_occurs_in(i, _))
    t.Row(fields, _) ->
      fields
      |> list.map(fn(x: #(String, t.Monotype)) { x.1 })
      |> list.any(do_occurs_in(i, _))
  }
}

fn next_unbound(state) {
  let Typer(next_unbound: i, ..) = state
  let state = Typer(..state, next_unbound: i + 1)
  #(i, state)
}

// monotype function??
// This will need the checker/unification/constraints data structure as it uses subsitutions and updates the next var value
// next unbound inside mono can be integer and unbound(i) outside
pub fn unify(expected, given, state) {
  // Pass as tuple to make reduce functions easier to implement
  // scope path is not modified through unification
  let #(typer, scope): #(Typer, Scope) = state
  let Typer(substitutions: substitutions, ..) = typer
  let expected = t.resolve(expected, substitutions)
  let given = t.resolve(given, substitutions)

  case occurs_in(expected, given) || occurs_in(given, expected) {
    True -> Ok(typer)
    False ->
      case expected, given {
        t.Native(e), t.Native(g) if e == g -> Ok(typer)
        t.Native(_), t.Native(_) ->
          Error(#(UnmatchedTypes(expected, given), typer))
        t.Binary, t.Binary -> Ok(typer)
        t.Tuple(expected), t.Tuple(given) ->
          case list.zip(expected, given) {
            Error(#(expected, given)) ->
              Error(#(IncorrectArity(expected, given), typer))
            Ok(pairs) ->
              list.try_fold(
                pairs,
                typer,
                fn(pair, typer) {
                  let #(expected, given) = pair
                  unify(expected, given, #(typer, scope))
                },
              )
          }
        t.Unbound(i), any -> Ok(add_substitution(i, any, typer))
        any, t.Unbound(i) -> Ok(add_substitution(i, any, typer))
        t.Row(expected, expected_extra), t.Row(given, given_extra) -> {
          let #(expected, given, shared) = group_shared(expected, given)
          let #(x, typer) = next_unbound(typer)
          try typer = case given, expected_extra {
            [], _ -> Ok(typer)
            only, Some(i) ->
              Ok(add_substitution(i, t.Row(only, Some(x)), typer))
            only, None -> Error(#(UnexpectedFields(only), typer))
          }
          try typer = case expected, given_extra {
            [], _ -> Ok(typer)
            only, Some(i) ->
              Ok(add_substitution(i, t.Row(only, Some(x)), typer))
            only, None -> Error(#(MissingFields(only), typer))
          }
          list.try_fold(
            shared,
            typer,
            fn(pair, typer) {
              let #(expected, given) = pair
              unify(expected, given, #(typer, scope))
            },
          )
        }
        t.Function(expected_from, expected_return), t.Function(
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
    Ok(polytype) -> {
      let Typer(next_unbound: next_unbound, ..) = typer
      let #(monotype, next_unbound) =
        polytype.instantiate(polytype, next_unbound)
      let typer = Typer(..typer, next_unbound: next_unbound)
      Ok(#(monotype, typer))
    }
    Error(Nil) -> Error(#(UnknownVariable(label), typer))
  }
}

fn set_variable(variable, typer, scope) {
  let #(label, monotype) = variable
  let Typer(substitutions: substitutions, ..) = typer
  let Scope(variables: variables, ..) = scope
  let polytype =
    polytype.generalise(t.resolve(monotype, substitutions), variables)
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

fn do_set_variable(variable, scope) {
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
    p.Discard -> {
      let #(x, typer) = next_unbound(typer)
      let type_var = t.Unbound(x)
      #(type_var, [], typer)
    }
    p.Variable(label) -> {
      let #(x, typer) = next_unbound(typer)
      let type_var = t.Unbound(x)
      #(type_var, [#(label, type_var)], typer)
    }
    p.Tuple(elements) -> {
      let #(elements, typer) = list.map_state(elements, typer, with_unbound)
      let expected = t.Tuple(list.map(elements, pairs_second))
      let elements = ones_with_real_keys(elements, [])
      #(expected, elements, typer)
    }
    p.Row(fields) -> {
      let #(fields, typer) = list.map_state(fields, typer, with_unbound)
      let extract_field_types = fn(named_field) {
        let #(#(name, _assignment), type_) = named_field
        #(name, type_)
      }
      let #(x, typer) = next_unbound(typer)
      let expected = t.Row(list.map(fields, extract_field_types), Some(x))
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
    type_: Result(t.Monotype, Reason),
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

pub fn get_type(tree: e.Expression(Metadata)) -> Result(t.Monotype, Reason) {
  let #(Metadata(type_: type_, ..), _) = tree
  type_
}

fn do_unify(expected, given, state) {
  let #(typer, scope): #(Typer, Scope) = state
  case unify(expected, given, state) {
    Ok(typer) -> #(Ok(expected), typer)
    // Don't think typer needs returning from unify?
    Error(#(reason, typer)) -> {
      let Typer(inconsistencies: inconsistencies, ..) = typer
      let inconsistencies = [
        #(scope.path, reason_to_string(reason)),
        ..typer.inconsistencies
      ]
      let typer = Typer(..typer, inconsistencies: inconsistencies)
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

fn with_unbound(thing: a, typer) -> #(#(a, t.Monotype), Typer) {
  let #(x, typer) = next_unbound(typer)
  let type_ = t.Unbound(x)
  #(#(thing, type_), typer)
}

pub fn equal_fn() {
  polytype.Polytype(
    [1, 2],
    t.Function(
      t.Tuple([t.Unbound(1), t.Unbound(1)]),
      // TODO Should the be part of parameterisation don't think so as not part of equal getting initialised
      t.Function(
        t.Row(
          [
            #("True", t.Function(t.Tuple([]), t.Unbound(2))),
            #("False", t.Function(t.Tuple([]), t.Unbound(2))),
          ],
          None,
        ),
        t.Unbound(2),
      ),
    ),
  )
}

pub fn infer_unconstrained(expression) {
  let typer = init()
  let scope =
    Scope(
      variables: [#("equal", equal_fn()), #("harness", harness.string())],
      path: path.root(),
    )
  let #(x, typer) = next_unbound(typer)
  let expected = t.Unbound(x)
  infer(expression, expected, #(typer, scope))
}

pub fn infer(
  expression: e.Expression(Nil),
  expected: t.Monotype,
  state: #(Typer, Scope),
) -> #(e.Expression(Metadata), Typer) {
  // return all context so more info can be added later
  let #(_, tree) = expression
  let #(typer, scope) = state
  let meta = Metadata(type_: _, scope: scope.variables, path: scope.path)
  case tree {
    e.Binary(value) -> {
      let #(type_, typer) = do_unify(expected, t.Binary, #(typer, scope))
      let expression = #(meta(type_), e.Binary(value))
      #(expression, typer)
    }
    e.Tuple(elements) -> {
      let #(pairs, typer) = list.map_state(elements, typer, with_unbound)
      let given = t.Tuple(list.map(pairs, pairs_second))
      let #(type_, typer) = do_unify(expected, given, #(typer, scope))
      // decided I want to match on top level first
      let #(elements, #(typer, _)) =
        list.map_state(
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
      let expression = #(meta(type_), e.Tuple(elements))
      #(expression, typer)
    }
    e.Row(fields) -> {
      let #(pairs, typer) = list.map_state(fields, typer, with_unbound)
      let given =
        t.Row(
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
        list.map_state(
          pairs,
          #(typer, 0),
          fn(pair, stz) {
            let #(tz, i) = stz
            let #(#(name, value), expected) = pair
            // let tz = Typer(..tz, location: path.append(path, i))
            let #(value, tz) =
              infer(value, expected, #(tz, child(child(scope, i), 1)))
            #(#(name, value), #(tz, i + 1))
          },
        )
      let expression = #(meta(type_), e.Row(fields))
      #(expression, typer)
    }
    e.Variable(label) -> {
      // Returns typer because of instantiation,
      // TODO separate lookup for instantiate, good for let rec
      let #(type_, typer) = case get_variable(label, typer, scope) {
        Ok(#(given, typer)) -> do_unify(expected, given, #(typer, scope))
        Error(#(reason, _)) -> {
          let Typer(inconsistencies: inconsistencies, ..) = typer
          let inconsistencies = [
            #(scope.path, reason_to_string(reason)),
            ..typer.inconsistencies
          ]
          let typer = Typer(..typer, inconsistencies: inconsistencies)
          #(Error(reason), typer)
        }
      }
      let expression = #(meta(type_), e.Variable(label))
      #(expression, typer)
    }
    e.Let(pattern, value, then) -> {
      let #(value, state) = case pattern, value {
        p.Variable(label), #(_, e.Function(pattern, body)) -> {
          let #(arg_type, bound_variables, typer) = pattern_type(pattern, typer)
          let #(y, typer) = next_unbound(typer)
          let return_type = t.Unbound(y)
          let given = t.Function(arg_type, return_type)
          // expected is value of let here don't unify that
          // let #(type_, typer) = do_unify(expected, given, typer)
          let bound_variables =
            list.map(
              bound_variables,
              fn(bv) {
                let #(label, monotype) = bv
                let polytype =
                  polytype.generalise(
                    t.resolve(monotype, typer.substitutions),
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
          // io.debug(t.resolve(given, typer.substitutions) == given)
          // let [#("f", x), .._] = typer.variables
          // io.debug(x.monotype)
          // // let True = x == given
          // io.debug(t.resolve(x.monotype, typer.substitutions))
          // io.debug("===========")
          // io.debug(t.resolve(given, typer.substitutions))
          // Set again after clearing out in the middle
          let scope = set_variable(#(label, given), typer, scope)
          // There are ALOT more type variables if handling all the errors.
          #(#(meta(Ok(given)), e.Function(pattern, return)), #(typer, scope))
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
                    t.resolve(monotype, typer.substitutions),
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
      let expression = #(meta(Ok(expected)), e.Let(pattern, value, then))
      #(expression, typer)
    }
    e.Function(pattern, body) -> {
      let #(arg_type, bound_variables, typer) = pattern_type(pattern, typer)
      let #(y, typer) = next_unbound(typer)
      let return_type = t.Unbound(y)
      let given = t.Function(arg_type, return_type)
      let #(type_, typer) = do_unify(expected, given, #(typer, scope))
      let bound_variables =
        list.map(
          bound_variables,
          fn(bv) {
            let #(label, monotype) = bv
            let polytype =
              polytype.generalise(
                t.resolve(monotype, typer.substitutions),
                scope.variables,
              )
            #(label, polytype)
          },
        )
      let scope = list.fold(bound_variables, scope, do_set_variable)
      let #(return, typer) = infer(body, return_type, #(typer, child(scope, 1)))
      // There are ALOT more type variables if handling all the errors.
      #(#(meta(type_), e.Function(pattern, return)), typer)
    }
    e.Call(function, with) -> {
      let #(x, typer) = next_unbound(typer)
      let arg_type = t.Unbound(x)
      let expected_function = t.Function(arg_type, expected)
      let #(function, typer) =
        infer(function, expected_function, #(typer, child(scope, 0)))
      let #(with, typer) = infer(with, arg_type, #(typer, child(scope, 1)))
      // Type is always! OK at this level
      let expression = #(meta(Ok(expected)), e.Call(function, with))
      #(expression, typer)
    }
    e.Provider(config, generator) -> {
      let typer = case generator {
        e.Hole ->
          Typer(
            ..typer,
            inconsistencies: [
              #(scope.path, "todo: implementation missing"),
              ..typer.inconsistencies
            ],
          )
        _ -> typer
      }
      let expression = #(meta(Ok(expected)), e.Provider(config, generator))
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
