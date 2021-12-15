import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
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
      |> string.join

    UnexpectedFields(expected) -> "unexpectedfields"
  }
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
pub fn unify(expected, given, typer) {
  let State(substitutions: substitutions, ..) = typer
  let expected = monotype.resolve(expected, substitutions)
  let given = monotype.resolve(given, substitutions)

  case occurs_in(expected, given) || occurs_in(given, expected) {
    True -> Ok(typer)
    False ->
      // io.debug("-----")
      // io.debug(expected)
      // io.debug(given)
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

// No generalization
fn set_self_variable(variable, state) {
  let #(label, monotype) = variable
  let State(variables: variables, substitutions: substitutions, ..) = state
  let polytype =
    // polytype.generalise(monotype.resolve(monotype, substitutions), state)
    // io.debug(polytype)
    polytype.Polytype([], monotype)
  let variables = [#(label, polytype), ..variables]
  State(..state, variables: variables, substitutions: substitutions)
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
      let #(elements, typer) = list.map_state(elements, typer, with_unbound)
      let expected = monotype.Tuple(list.map(elements, pairs_second))
      let elements = ones_with_real_keys(elements, [])
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
  State(..typer, location: path.append(location, i))
}

pub type Metadata {
  Metadata(
    type_: Result(monotype.Monotype, Reason),
    scope: List(#(String, polytype.Polytype)),
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

fn do_unify(expected, given, typer) {
  case unify(expected, given, typer) {
    Ok(typer) -> #(Ok(expected), typer)
    // Don't think typer needs returning from unify?
    Error(#(reason, typer)) -> {
      let State(inconsistencies: inconsistencies, ..) = typer
      let inconsistencies = [reason_to_string(reason), ..typer.inconsistencies]
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
  let typer = init([#("equal", equal_fn())])
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
  let meta = Metadata(type_: _, scope: typer.variables)
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
            let tz = State(..tz, location: path.append(path, i))
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
            let tz = State(..tz, location: path.append(path, i))
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
        Error(#(reason, _)) -> {
          let State(inconsistencies: inconsistencies, ..) = typer
          let inconsistencies = [
            reason_to_string(reason),
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
      let State(variables: variables, location: location, ..) = typer
      let #(value, typer) = case pattern, value {
        pattern.Variable(label), #(_, Function(pattern, body)) -> {
          let #(arg_type, bound_variables, typer) = pattern_type(pattern, typer)
          let #(y, typer) = polytype.next_unbound(typer)
          let return_type = monotype.Unbound(y)
          let given = monotype.Function(arg_type, return_type)
          // expected is value of let here don't unify that
          // let #(type_, typer) = do_unify(expected, given, typer)
          let State(variables: variables, location: location, ..) = typer
          let typer = list.fold(bound_variables, typer, set_variable)
          let typer = set_self_variable(#(label, given), typer)
          let #(return, typer) = infer(body, return_type, append_path(typer, 0))
          // io.debug(given)
          // io.debug(monotype.resolve(given, typer.substitutions) == given)
          // let [#("f", x), .._] = typer.variables
          // io.debug(x.monotype)
          // // let True = x == given
          // io.debug(monotype.resolve(x.monotype, typer.substitutions))
          // io.debug("===========")
          // io.debug(monotype.resolve(given, typer.substitutions))
          let typer = State(..typer, variables: variables, location: location)
          // Set again after clearing out in the middle
          let typer = set_variable(#(label, given), typer)
          // There are ALOT more type variables if handling all the errors.
          #(#(meta(Ok(given)), Function(pattern, return)), typer)
        }
        _, _ -> {
          let #(expected_value, bound_variables, typer) =
            pattern_type(pattern, typer)
          // TODO remove this nesting when we(if?) separate typer and scope
          let #(value, typer) =
            infer(value, expected_value, append_path(typer, 0))
          let typer = State(..typer, variables: variables, location: location)
          let typer = list.fold(bound_variables, typer, set_variable)
          #(value, typer)
        }
      }
      let #(then, typer) = infer(then, expected, append_path(typer, 1))
      // Let is always OK the error is on the term inside
      let expression = #(meta(Ok(expected)), Let(pattern, value, then))
      #(expression, typer)
    }

    Function(pattern, body) -> {
      let #(arg_type, bound_variables, typer) = pattern_type(pattern, typer)
      let #(y, typer) = polytype.next_unbound(typer)
      let return_type = monotype.Unbound(y)
      let given = monotype.Function(arg_type, return_type)
      let #(type_, typer) = do_unify(expected, given, typer)
      // TODO remove this nesting when we(if?) separate typer and scope
      let State(variables: variables, location: location, ..) = typer
      let typer = list.fold(bound_variables, typer, set_variable)
      let #(return, typer) = infer(body, return_type, append_path(typer, 0))
      let typer = State(..typer, variables: variables, location: location)
      // There are ALOT more type variables if handling all the errors.
      #(#(meta(type_), Function(pattern, return)), typer)
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
    Provider(config, generator) -> {
      let expression = #(meta(Ok(expected)), Provider(config, generator))
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
