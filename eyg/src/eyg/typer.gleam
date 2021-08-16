import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg/ast.{Binary, Call, Constructor, Function, Let, Row, Tuple, Variable}
import eyg/ast/pattern
import eyg/typer/monotype
import eyg/typer/polytype

// Context/typer
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
pub fn resolve(type_, unification) {
  let monotype.Unification(substitutions: substitutions, ..) = unification
  case type_ {
    monotype.Unbound(i) ->
      case list.key_find(substitutions, i) {
        Ok(monotype.Unbound(j)) if i == j -> type_
        Error(Nil) -> type_
        Ok(substitution) -> resolve(substitution, unification)
      }
    monotype.Binary -> monotype.Binary
    monotype.Tuple(elements) -> {
      let elements = list.map(elements, resolve(_, unification))
      monotype.Tuple(elements)
    }
    monotype.Row(fields, rest) -> {
      let resolved_fields =
        list.map(
          fields,
          fn(field) {
            let #(name, type_) = field
            #(name, resolve(type_, unification))
          },
        )
      case rest {
        None -> monotype.Row(resolved_fields, None)
        Some(i) ->
          case resolve(monotype.Unbound(i), unification) {
            monotype.Unbound(j) -> monotype.Row(resolved_fields, Some(j))
            monotype.Row(inner, rest) ->
              monotype.Row(list.append(resolved_fields, inner), rest)
          }
      }
    }
    monotype.Function(from, to) -> {
      let from = resolve(from, unification)
      let to = resolve(to, unification)
      monotype.Function(from, to)
    }
    monotype.Nominal(name, parameters) ->
      monotype.Nominal(name, list.map(parameters, resolve(_, unification)))
  }
}

fn add_substitution(variable, resolves, unification) {
  // let State(unification: unification, ..) = state
  let monotype.Unification(substitutions: substitutions, ..) = unification
  let substitutions = [#(variable, resolves), ..substitutions]
  let unification =
    monotype.Unification(..unification, substitutions: substitutions)
  // State(..state, unification: unification)
}

fn unify_pair(pair, checker) {
  let #(expected, given) = pair
  unify(expected, given, checker)
}

// monotype function??
fn unify(expected, given, checker) {
  let expected = resolve(expected, checker)
  let given = resolve(given, checker)
  case expected, given {
    monotype.Binary, monotype.Binary -> Ok(checker)
    monotype.Tuple(expected), monotype.Tuple(given) ->
      case list.zip(expected, given) {
        Error(#(expected, given)) -> Error(IncorrectArity(expected, given))
        Ok(pairs) -> list.try_fold(pairs, checker, unify_pair)
      }
    monotype.Unbound(i), any -> Ok(add_substitution(i, any, checker))
    any, monotype.Unbound(i) -> Ok(add_substitution(i, any, checker))
    monotype.Row(expected, expected_extra), monotype.Row(given, given_extra) -> {
      let #(expected, given, shared) = group_shared(expected, given)
      let #(x, checker) = monotype.next_unbound(checker)
      try checker = case given, expected_extra {
        [], _ -> Ok(checker)
        only, Some(i) ->
          Ok(add_substitution(i, monotype.Row(only, Some(x)), checker))
        only, None -> Error(MissingFields(only))
      }
      try checker = case expected, given_extra {
        [], _ -> Ok(checker)
        only, Some(i) ->
          Ok(add_substitution(i, monotype.Row(only, Some(x)), checker))
        only, None -> Error(MissingFields(only))
      }
      list.try_fold(shared, checker, unify_pair)
    }
    monotype.Function(expected_from, expected_return), monotype.Function(
      given_from,
      given_return,
    ) -> {
      try checker = unify(expected_from, given_from, checker)
      unify(expected_return, given_return, checker)
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
fn get_variable(label, scope, checker) {
  case list.key_find(scope, label) {
    Ok(polytype) -> Ok(polytype.instantiate(polytype, checker))
    Error(Nil) -> Error(UnknownVariable(label))
  }
}

fn set_variable(label, monotype, scope, checker) {
  let polytype = polytype.generalise(monotype)
  let scope = [#(label, polytype), ..scope]
  #(scope, checker)
}

// assignment/patterns
fn match_pattern(pattern, given, scope, checker) {
  case pattern {
    pattern.Variable(label) -> Ok(set_variable(label, given, scope, checker))
    pattern.Tuple(elements) -> {
      let #(types, #(scope, checker)) =
        list.map_state(
          elements,
          #(scope, checker),
          fn(label, state) {
            let #(scope, checker) = state
            let #(x, checker) = monotype.next_unbound(checker)
            let type_var = monotype.Unbound(x)
            let #(scope, checker) =
              set_variable(label, type_var, scope, checker)
            #(type_var, #(scope, checker))
          },
        )
      let expected = monotype.Tuple(types)
      try checker = unify(expected, given, checker)
      Ok(#(scope, checker))
    }
    pattern.Row(fields) -> {
      let #(typed_fields, #(scope, checker)) =
        list.map_state(
          fields,
          #(scope, checker),
          fn(field, state) {
            let #(scope, checker) = state
            let #(name, label) = field
            let #(x, checker) = monotype.next_unbound(checker)
            let type_var = monotype.Unbound(x)
            let #(scope, checker) =
              set_variable(label, type_var, scope, checker)
            #(#(name, type_var), #(scope, checker))
          },
        )
      let #(x, checker) = monotype.next_unbound(checker)
      let expected = monotype.Row(typed_fields, Some(x))
      try checker = unify(expected, given, checker)
      Ok(#(scope, checker))
    }
  }
}

// inference fns
fn infer_field(field, scope, checker) {
  let #(name, tree) = field
  try #(type_, checker) = do_infer(tree, scope, checker)
  Ok(#(#(name, type_), checker))
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

pub fn infer(tree, scope) {
  try #(type_, checker) = do_infer(tree, scope, monotype.checker())
  Ok(resolve(type_, checker))
}

fn do_infer(
  tree: ast.Node,
  scope: List(#(String, polytype.Polytype)),
  checker: monotype.Unification,
) -> Result(#(monotype.Monotype, monotype.Unification), Reason) {
  case tree {
    Binary(_) -> Ok(#(monotype.Binary, checker))
    Tuple(elements) -> {
      try #(types, checker) =
        list.try_map_state(
          elements,
          checker,
          fn(e, checker) { do_infer(e, scope, checker) },
        )
      Ok(#(monotype.Tuple(types), checker))
    }
    Row(fields) -> {
      try #(types, checker) =
        list.try_map_state(
          fields,
          checker,
          fn(field, checker) { infer_field(field, scope, checker) },
        )
      Ok(#(monotype.Row(types, None), checker))
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
              let #(monotype, checker) = polytype.instantiate(p, checker)
              Ok(#(monotype, checker))
            }
            Error(Nil) -> Error(UnknownVariant(variant, named))
          }
        Error(Nil) -> Error(UnknownType(named))
      }
    Variable(label) -> {
      try #(type_, checker) = get_variable(label, scope, checker)
      Ok(#(type_, checker))
    }
    Let(pattern, value, then) -> {
      try #(value_type, checker) = do_infer(value, scope, checker)
      try #(scope, checker) = match_pattern(pattern, value_type, scope, checker)
      do_infer(then, scope, checker)
    }
    Function(label, body) -> {
      let #(x, checker) = monotype.next_unbound(checker)
      let type_var = monotype.Unbound(x)
      let #(scope, checker) = set_variable(label, type_var, scope, checker)
      try #(return, checker) = do_infer(body, scope, checker)
      Ok(#(monotype.Function(type_var, return), checker))
    }
    Call(function, with) -> {
      try #(function_type, checker) = do_infer(function, scope, checker)
      try #(with_type, checker) = do_infer(with, scope, checker)
      let #(x, checker) = monotype.next_unbound(checker)
      let return_type = monotype.Unbound(x)
      try checker =
        unify(function_type, monotype.Function(with_type, return_type), checker)
      Ok(#(return_type, checker))
    }
  }
}
