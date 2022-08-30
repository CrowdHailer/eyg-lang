import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/int
import gleam/list
import misc
import gleam/option.{None, Some}
import gleam/pair
import gleam/string
import eyg/ast
import eyg/ast/path
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype as t
import eyg/typer/polytype
import eyg/typer/harness

pub type Reason {
  IncorrectArity(expected: Int, given: Int)
  UnknownVariable(label: String)
  UnmatchedTypes(expected: t.Monotype, given: t.Monotype)
  MissingFields(expected: List(#(String, t.Monotype)))
  UnexpectedFields(unexpected: List(#(String, t.Monotype)))
  ProviderFailed(generator: e.Generator, expected: t.Monotype)
  GeneratedInvalid(errors: List(#(List(Int), Reason)))
  Warning(message: String)
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
    inconsistencies: List(#(List(Int), Reason)),
  )
}

// I think the types should be concerned only with types, no redering
pub fn init() {
  Typer(0, [], [])
}

pub fn next_unbound(typer) {
  let Typer(next_unbound: i, ..) = typer
  let typer = Typer(..typer, next_unbound: i + 1)
  #(i, typer)
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
    Error(Nil) -> Error(UnknownVariable(label))
  }
}

fn set_variable(variable, typer, scope) {
  let #(label, monotype) = variable
  let Typer(substitutions: substitutions, ..) = typer
  let Scope(variables: variables, ..) = scope
  let resolved = t.resolve(monotype, substitutions)
  let polytype = polytype.generalise(resolved, variables)
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
    [#("", _), ..rest] -> ones_with_real_keys(rest, done)
    [#(label, monotype), ..rest] ->
      ones_with_real_keys(rest, [#(label, monotype), ..done])
  }
}

fn pattern_type(pattern, typer) {
  case pattern {
    p.Variable("") -> {
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
      let #(elements, typer) = misc.map_state(elements, typer, with_unbound)
      let expected = t.Tuple(list.map(elements, pair.second))
      let elements = ones_with_real_keys(elements, [])
      #(expected, elements, typer)
    }
    p.Record(fields) -> {
      let #(fields, typer) = misc.map_state(fields, typer, with_unbound)
      let extract_field_types = fn(named_field) {
        let #(#(name, _assignment), type_) = named_field
        #(name, type_)
      }
      let #(x, typer) = next_unbound(typer)
      let expected = t.Record(list.map(fields, extract_field_types), Some(x))
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

pub fn get_type(
  tree: e.Expression(Metadata, a),
) -> Result(t.Monotype, Reason) {
  let #(Metadata(type_: type_, ..), _) = tree
  type_
}

pub fn do_unify(
  state: #(Typer, List(Int)),
  pair: #(t.Monotype, t.Monotype),
) -> Result(#(Typer, List(Int)), Reason) {
  let #(t1, t2) = pair
  let #(state, seen) = state
  case t1, t2 {
    t.Unbound(i), t.Unbound(j) if i == j -> Ok(#(state, seen))
    // Need to keep reference to variables for resolving recursive types
    t.Unbound(i), t.Unbound(j) ->
      case list.key_find(state.substitutions, i) {
        Ok(r1) ->
          case list.key_find(state.substitutions, j) {
            Ok(r2) -> do_unify(#(state, [i, j, ..seen]), #(r1, r2))
            Error(_) -> Ok(add_substitution(j, t1, #(state, seen)))
          }
        Error(_) -> Ok(add_substitution(i, t2, #(state, seen)))
      }

    t.Unbound(i), _ ->
      case list.key_find(state.substitutions, i) {
        Ok(t1) ->
          case list.contains(seen, i) {
            False -> do_unify(#(state, [i, ..seen]), #(t1, t2))
            True -> Ok(#(state, seen))
          }
        Error(Nil) -> Ok(add_substitution(i, t2, #(state, seen)))
      }
    _, t.Unbound(j) ->
      case list.key_find(state.substitutions, j) {
        Ok(t2) ->
          case list.contains(seen, j) {
            False -> do_unify(#(state, [j, ..seen]), #(t1, t2))
            True -> Ok(#(state, seen))
          }
        Error(Nil) -> Ok(add_substitution(j, t1, #(state, seen)))
      }
    t.Recursive(i, inner1), t.Recursive(j, inner2) -> {
      let inner2 = polytype.replace_variable(inner2, j, i)
      do_unify(#(state, seen), #(inner1, inner2))
    }
    t.Recursive(i, inner), _ -> {
      let t1 = polytype.replace_type(inner, i, t1)
      do_unify(#(state, seen), #(t1, t2))
    }
    _, t.Recursive(i, inner) -> {
      let t2 = polytype.replace_type(inner, i, t2)
      do_unify(#(state, seen), #(t1, t2))
    }
    t.Native(n1,i1), t.Native(n2,i2) -> {
      case n1 == n2 {
        True -> case list.strict_zip(i1, i2) {
          Ok(pairs) -> list.try_fold(pairs, #(state, seen), do_unify)
          Error(list.LengthMismatch) ->
            Error(IncorrectArity(list.length(i1), list.length(i2)))
        }
        False -> Error(UnmatchedTypes(t.Native(n1,i1), t.Native(n2,i2)))
      }
    }
    t.Binary, t.Binary -> Ok(#(state, seen))
    t.Tuple(e1), t.Tuple(e2) ->
      case list.strict_zip(e1, e2) {
        Ok(pairs) -> list.try_fold(pairs, #(state, seen), do_unify)
        Error(list.LengthMismatch) ->
          Error(IncorrectArity(list.length(e1), list.length(e2)))
      }
    t.Record(row1, extra1), t.Record(row2, extra2) -> {
      let #(unmatched1, unmatched2, shared) = group_shared(row1, row2)
      let #(next, state) = next_unbound(state)
      try #(state, seen) = case unmatched2, extra1 {
        [], _ -> Ok(#(state, seen))
        only, Some(i) ->
          Ok(add_substitution(i, t.Record(only, Some(next)), #(state, seen)))
        only, None -> Error(UnexpectedFields(only))
      }
      try #(state, seen) = case unmatched1, extra2 {
        // TODO handle extra's the same as in Union
        [], _ -> Ok(#(state, seen))
        only, Some(i) ->
          Ok(add_substitution(i, t.Record(only, Some(next)), #(state, seen)))
        only, None -> Error(MissingFields(only))
      }
      list.try_fold(shared, #(state, seen), do_unify)
    }
    t.Union(row1, extra1), t.Union(row2, extra2) -> {
      let #(unmatched1, unmatched2, shared) = group_shared(row1, row2)
      let #(next, state) = next_unbound(state)
      try #(state, seen) = case unmatched2, extra1 {
        [], None -> Ok(#(state, seen))
        only, Some(i) ->
          Ok(add_substitution(
            i,
            t.Union(
              only,
              case extra2 {
                Some(_) -> Some(next)
                None -> None
              },
            ),
            #(state, seen),
          ))
        only, None -> Error(UnexpectedFields(only))
      }
      try #(state, seen) = case unmatched1, extra2 {
        [], None -> Ok(#(state, seen))
        only, Some(i) ->
          Ok(add_substitution(
            i,
            t.Union(
              only,
              case extra1 {
                Some(_) -> Some(next)
                None -> None
              },
            ),
            #(state, seen),
          ))
        only, None -> Error(MissingFields(only))
      }
      list.try_fold(shared, #(state, seen), do_unify)
    }
    t.Function(from1, to1, effects1), t.Function(from2, to2, effects2) -> {
      try #(state, seen) = do_unify(#(state, seen), #(from1, from2))
      try #(state, seen) = do_unify(#(state, seen), #(effects1, effects2))
      do_unify(#(state, seen), #(to1, to2))
    }
    _, _ -> Error(UnmatchedTypes(t1, t2))
  }
}

fn add_substitution(
  i,
  type_,
  state: #(Typer, List(Int)),
) -> #(Typer, List(Int)) {
  let #(state, seen) = state
  case t.resolve(type_, state.substitutions) {
    t.Unbound(j) if j == i -> #(state, seen)
    _ -> {
      let substitutions = [#(i, type_), ..state.substitutions]
      #(Typer(..state, substitutions: substitutions), seen)
    }
  }
}

pub fn unify(t1, t2, state: Typer) {
  try #(state, seen) = do_unify(#(state, []), #(t1, t2))
  Ok(state)
}

fn with_unbound(thing: a, typer) -> #(#(a, t.Monotype), Typer) {
  let #(x, typer) = next_unbound(typer)
  let type_ = t.Unbound(x)
  #(#(thing, type_), typer)
}

fn fresh(typer) {
  let #(x, typer) = next_unbound(typer)
  let type_ = t.Unbound(x)
  #(type_, typer)
}

// TODO move to lib typer/std
// remove all references to "True" "Some" "Ok"
pub fn equal_fn() {
  polytype.Polytype(
    [1, 2],
    t.Function(
      t.Tuple([t.Unbound(1), t.Unbound(1)]),
      t.Union([#("True", t.Tuple([])), #("False", t.Tuple([]))], None),
      t.open(2),
    ),
  )
}

// Make private and always put in infer?
pub fn expand_providers(tree, typer, scope) {
  let #(meta, expression) = tree
  case expression {
    // Binary and Variable are unstructured and restructured to change type of provider generated content
    e.Binary(value) -> #(#(meta, e.Binary(value)), typer)
    e.Variable(value) -> #(#(meta, e.Variable(value)), typer)
    e.Tuple(elements) -> {
      let #(elements, typer) =
        misc.map_state(
          elements,
          typer,
          fn(e, typer) { expand_providers(e, typer, scope) },
        )
      #(#(meta, e.Tuple(elements)), typer)
    }
    e.Record(fields) -> {
      let #(fields, typer) =
        misc.map_state(
          fields,
          typer,
          fn(field, typer) {
            let #(key, value) = field
            let #(value, typer) = expand_providers(value, typer, scope)
            let field = #(key, value)
            #(field, typer)
          },
        )
      #(#(meta, e.Record(fields)), typer)
    }
    e.Access(value, label) -> {
      let #(value, typer) = expand_providers(value, typer, scope)
      #(#(meta, e.Access(value, label)), typer)
    }
    e.Tagged(tag, value) -> {
      let #(value, typer) = expand_providers(value, typer, scope)
      #(#(meta, e.Tagged(tag, value)), typer)
    }
    e.Let(label, value, then) -> {
      let #(value, typer) = expand_providers(value, typer, scope)
      let #(then, typer) = expand_providers(then, typer, scope)
      #(#(meta, e.Let(label, value, then)), typer)
    }
    e.Function(from, to) -> {
      // let #(from, typer) = expand_providers(from, typer)
      let #(to, typer) = expand_providers(to, typer, scope)
      #(#(meta, e.Function(from, to)), typer)
    }
    e.Call(func, with) -> {
      let #(func, typer) = expand_providers(func, typer, scope)
      let #(with, typer) = expand_providers(with, typer, scope)
      #(#(meta, e.Call(func, with)), typer)
    }
    e.Case(value, branches) -> {
      let #(value, typer) = expand_providers(value, typer, scope)
      let #(branches, typer) =
        misc.map_state(
          branches,
          typer,
          fn(branch, typer) {
            let #(key, pattern, then) = branch
            let #(then, typer) = expand_providers(then, typer, scope)
            let branch = #(key, pattern, then)
            #(branch, typer)
          },
        )
      #(#(meta, e.Case(value, branches)), typer)
    }

    // Hole needs to be separate, it can't be a function call because it is not always going to be a function that gets called.
    e.Hole -> #(#(meta, e.Hole), typer)
    // Only expand providers one level
    e.Provider(config, g, _) -> {
      let Metadata(type_: Ok(expected), ..) = meta
      let Typer(substitutions: substitutions, ..) = typer
      let expected = t.resolve(expected, substitutions)
      // TODO can providers produce effects
      case e.generate(g, config, expected) {
        Ok(tree) -> {
          let state = Scope(variables: scope, path: meta.path)
          let previous_errors = list.length(typer.inconsistencies)
          let #(typed, typer) = infer(tree, expected, t.empty, #(typer, state))
          let extra = list.length(typer.inconsistencies) - previous_errors
          // New inconsistencies pushed on font
          let new_errors = list.take(typer.inconsistencies, extra)
          let old_errors = list.drop(typer.inconsistencies, extra)
          let #(meta, typer) = case new_errors {
            [] -> #(meta, typer)
            _ -> {
              let reason = GeneratedInvalid(new_errors)
              let meta = Metadata(..meta, type_: Error(reason))
              let new = #(meta.path, reason)
              let inconsistencies = [new, ..old_errors]
              let typer = Typer(..typer, inconsistencies: inconsistencies)
              #(meta, typer)
            }
          }
          #(#(meta, e.Provider(config, g, typed)), typer)
        }
        Error(Nil) -> {
          let Metadata(path: path, ..) = meta
          let Typer(inconsistencies: inconsistencies, ..) = typer
          let inconsistencies = [
            #(path, ProviderFailed(g, expected)),
            ..inconsistencies
          ]
          let typer = Typer(..typer, inconsistencies: inconsistencies)
          // This only exists because Loader and Hole need special treatment
          let dummy = #(dynamic.from(Nil), e.Hole)
          let #(typed, _typer) =
            infer(dummy, expected, t.empty, #(typer, root_scope([])))
          let meta =
            Metadata(
              ..meta,
              type_: Error(ProviderFailed(expected: expected, generator: g)),
            )
          #(#(meta, e.Provider(config, g, typed)), typer)
        }
      }
    }
  }
}

fn try_unify(expected, given, typer, path) {
  case unify(expected, given, typer) {
    Ok(typer) -> #(Ok(expected), typer)
    Error(reason) -> {
      let inconsistencies = [#(path, reason), ..typer.inconsistencies]
      let typer = Typer(..typer, inconsistencies: inconsistencies)
      #(Error(reason), typer)
    }
  }
}

// expected is the type this expression should evaluate too
pub fn infer(
  expression: e.Expression(Dynamic, Dynamic),
  expected: t.Monotype, 
  effects: t.Monotype,
  state: #(Typer, Scope),
) -> #(e.Expression(Metadata, Dynamic), Typer) {
  let #(_, tree) = expression
  let #(typer, scope) = state
  let meta = Metadata(type_: _, scope: scope.variables, path: scope.path)
  case tree {
    e.Binary(value) -> {
      let #(result, typer) = try_unify(expected, t.Binary, typer, scope.path)
      let expression = #(meta(result), e.Binary(value))
      #(expression, typer)
    }
    e.Tuple(elements) -> {
      let #(pairs, typer) = misc.map_state(elements, typer, with_unbound)
      let given = t.Tuple(list.map(pairs, pair.second))
      let #(type_, typer) = try_unify(expected, given, typer, scope.path)
      // decided I want to match on top level first
      let #(elements, #(typer, _)) =
        misc.map_state(
          pairs,
          #(typer, 0),
          fn(pair, stz) {
            let #(tz, i) = stz
            let #(element, expected) = pair
            let #(element, tz) =
              infer(element, expected, effects, #(tz, child(scope, i)))
            #(element, #(tz, i + 1))
          },
        )
      let expression = #(meta(type_), e.Tuple(elements))
      #(expression, typer)
    }
    e.Record(fields) -> {
      let #(pairs, typer) = misc.map_state(fields, typer, with_unbound)
      let given =
        t.Record(
          list.map(
            pairs,
            fn(pair) {
              let #(#(name, _value), type_) = pair
              #(name, type_)
            },
          ),
          None,
        )
      let #(type_, typer) = try_unify(expected, given, typer, scope.path)
      let #(fields, #(typer, _)) =
        misc.map_state(
          pairs,
          #(typer, 0),
          fn(pair, stz) {
            let #(tz, i) = stz
            let #(#(name, value), expected) = pair
            let #(value, tz) =
              infer(value, expected, effects, #(tz, child(child(scope, i), 1)))
            #(#(name, value), #(tz, i + 1))
          },
        )
      let expression = #(meta(type_), e.Record(fields))
      #(expression, typer)
    }
    e.Access(value, label) -> {
      let #(t, typer) = next_unbound(typer)
      let field_type = t.Unbound(t)
      let #(t, typer) = next_unbound(typer)
      let record_type = t.Record([#(label, field_type)], Some(t))
      let #(type_, typer) = try_unify(expected, field_type, typer, scope.path)
      let #(value, typer) = infer(value, record_type, effects, #(typer, child(scope, 0)))
      // do records have labels or keys?
      let expression = #(meta(type_), e.Access(value, label))
      #(expression, typer)
    }
    e.Tagged(tag, value) -> {
      let #(x, typer) = next_unbound(typer)
      let value_type = t.Unbound(x)
      let #(y, typer) = next_unbound(typer)
      let given = t.Union([#(tag, value_type)], Some(y))
      let #(type_, typer) = try_unify(expected, given, typer, scope.path)
      let #(value, typer) = infer(value, value_type, effects, #(typer, child(scope, 1)))
      let expression = #(meta(type_), e.Tagged(tag, value))
      #(expression, typer)
    }
    e.Variable(label) if label == "do" || label == "impl" -> {
      let expression = #(meta(Ok(expected)), e.Variable(label))
      #(expression, typer)
    }
    e.Variable(label) -> {
      let #(type_, typer) = case get_variable(label, typer, scope) {
        Ok(#(given, typer)) -> try_unify(expected, given, typer, scope.path)
        Error(reason) -> {
          let Typer(inconsistencies: inconsistencies, ..) = typer
          let inconsistencies = [#(scope.path, reason), ..inconsistencies]
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
          let #(x, typer) = next_unbound(typer)
          let arg_type = t.Unbound(x)
          let #(y, typer) = next_unbound(typer)
          let return_type = t.Unbound(y)
          let #(z, typer) = next_unbound(typer)
          let effect_type = t.Unbound(z)

          // TODO test effects in optionally reursive functions
          let self_type = t.Function(arg_type, return_type, effect_type)
          let inner_scope = set_self_variable(#(label, self_type), scope)
          let #(body, typer, type_) =
            infer_function(
              pattern,
              body,
              self_type,
              typer,
              child(inner_scope, 1),
              1,
            )
          let typer: Typer = typer
          let scope = set_variable(#(label, self_type), typer, scope)
          #(#(meta(type_), e.Function(pattern, body)), #(typer, scope))
        }
        _, _ -> {
          let #(expected_value, bound_variables, typer) =
            pattern_type(pattern, typer)
          let #(value, typer) =
            infer(value, expected_value, effects, #(typer, child(scope, 1)))
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
      // This is essentially an instantiation
      // assert effects = t.resolve(effects, typer.substitutions)
      
      let #(then, typer) = infer(then, expected, effects, #(typer, scope))
      // Let is always OK the error is on the term inside
      let expression = #(meta(Ok(expected)), e.Let(pattern, value, then))
      #(expression, typer)
    }
    e.Function(pattern, body) -> {
      // There are ALOT more type variables if handling all the errors.
      let #(body, typer, type_) =
        infer_function(pattern, body, expected, typer, scope, 1)
      #(#(meta(type_), e.Function(pattern, body)), typer)
    }
    // this is a specific keyword, we could have keyword pluggable and then allow overwriting of keyword. But why do that
    e.Call(#(_, e.Variable("do")), with) -> {
      let #(x, typer) = next_unbound(typer)
      let arg_type = t.Union([], Some(x))
      let #(with, typer) = infer(with, arg_type, effects, #(typer, child(scope, 1)))

      let #(y, typer) = next_unbound(typer)
      let function_type = t.Unbound(y)

      let #(r, typer) = case get_type(with) {
        Ok(type_) -> {
          case t.resolve(type_, typer.substitutions) {
            t.Union([#(name, value)], Some(extra)) -> {
              // All the effect variants need to be known when deciding the type of the effect keyword.
              // This unification ensures that the union is closed
              let #(_, typer) = try_unify(t.Unbound(extra), t.Union([], None), typer, child(scope, 1).path)

              let #(z, typer) = next_unbound(typer)
              // Tuple as unit for pure effects, I think this is the type of the continuation
              let raised = t.Union([#(name, t.Function(value, expected, t.Tuple([])))], Some(z))

              // Can unify with an unbound value for raised so that we show the call is at least a function
              let expected_function = t.Function(arg_type, expected, raised)
              let #(r1, typer) = try_unify(function_type, expected_function, typer,  child(scope, 0).path)

              let #(r2, typer) = try_unify(effects, raised, typer, child(scope, 0).path)
              // TODO test errors are kept
              let r = case r1, r2 {
                Ok(_), Ok(_) -> r1
                Error(_), _ -> r1
                _, _ -> r2
              }
              #(r, typer)
            }
            t -> {
              let reason = case t {
                t.Union([],_ ) -> MissingFields([#("Effect", t.Unbound(-100))]) 
                t.Union(fields, _) -> UnexpectedFields(fields)
                _ -> UnmatchedTypes(t.Union([#("Effect", t.Unbound(-100))], None), t)
              }
              let inconsistencies = [#(child(scope, 1).path, reason), ..typer.inconsistencies]
              let typer = Typer(..typer, inconsistencies: inconsistencies)
              #(Error(reason), typer)
            }
          }

        }
        Error(reason) -> #(Ok(function_type), typer)
      }

      let expression = #(meta(Ok(expected)), e.Call(#(meta(r), e.Variable("do")), with))
      #(expression, typer)
    }
    e.Call(#(_, e.Variable("catch")), with) -> {
      // x: union of effects handled in this catch block
      let #(x, typer) = next_unbound(typer)
      // y/handled_return: value each branch of the handler must return and final return value
      let #(y, typer) = next_unbound(typer)
      let handled_return = t.Unbound(y)
            
      let #(z, typer) = next_unbound(typer)
      let computation_arg = t.Unbound(z)
      // a/computation_return value of the computed being executed with out effect raised
      let #(a, typer) = next_unbound(typer)
      let computation_return = t.Unbound(a)
      // // b/inner_effects: the set of effects available to the computation, should only include external effects when actually called
      // let #(b, typer) = next_unbound(typer)
      let #(c, typer) = next_unbound(typer)
      let unhandled_effects = t.Union([], Some(c))
      // effect arg type/might be n of these
      let #(d, typer) = next_unbound(typer)
      let effect_arg = t.Unbound(d)
      let #(e, typer) = next_unbound(typer)
      let effect_return = t.Unbound(e)


      let handler_type = t.Function(t.Union([#("Return", computation_return)], Some(x)), handled_return, unhandled_effects)

      let #(_, temp_typer) = infer(with, handler_type, effects, #(typer, child(scope, 1)))
      let #(inner_effects, handler_type) = case t.resolve(t.Unbound(x), temp_typer.substitutions) {
        t.Union([#(name, _)], None) -> {
          // c = unhandled_effects
          let inner_effects = t.Union([#(name, t.Function(effect_arg, effect_return, unhandled_effects))], Some(c))
          // TODO this is probably outer effects because you need to call catch again
          // This should get resolved with unification for a raise
          // The raise needs to handle if we have a continuation effect
          // unhandled_effects needed here I'm pretty sure
          let continuation_type = t.Function(effect_return, computation_return, inner_effects)
          let handler_type = t.Function(
            t.Union([#("Return", computation_return), #(name, t.Tuple([effect_arg, continuation_type]))], None), 
            handled_return, 
            unhandled_effects
          )
          #(inner_effects, handler_type)
        }
        // Maybe this shouldn't be empty
        t.Union([], None) -> {
          let handler_type = t.Function(t.Union([#("Return", computation_return), #("Effect", t.Unbound(-100))], Some(x)), handled_return, unhandled_effects)
          #(unhandled_effects, handler_type)
        }
        _ -> #(unhandled_effects, handler_type)
      }
      let #(with, typer) = infer(with, handler_type, effects, #(typer, child(scope, 1)))

      // type of final call
      let exec_type = t.Function(computation_arg, handled_return, unhandled_effects)
      let computation_type = t.Function(computation_arg, computation_return, inner_effects)
      let catcher_type = t.Function(computation_type, exec_type, t.Union([], None))
      // type to assign the catch function
      let function_type = t.Function(handler_type, catcher_type, effects)

      let given = catcher_type
      let #(_, typer) = try_unify(expected, given, typer, scope.path)

      let expression = #(meta(Ok(expected)), e.Call(#(meta(Ok(function_type)), e.Variable("catch")), with))
      #(expression, typer)
    }
    e.Call(function, with) -> {
      let #(x, typer) = next_unbound(typer)
      let arg_type = t.Unbound(x)
      let expected_function = t.Function(arg_type, expected, effects)

      // Is this where we should instantiate every effect list
      let #(function, typer) =
        infer(function, expected_function, effects, #(typer, child(scope, 0)))
      // This should be unecessary
      // assert effects = t.resolve(effects, typer.substitutions)
      // merge effects is different to ther function matching because it should be fixed
      // I think resolving is sensible Also test that open effect remains open forever

      
      let #(with, typer) = infer(with, arg_type,effects, #(typer, child(scope, 1)))
      // io.debug(#("---->", t.resolve(arg_type, typer.substitutions), t.resolve(expected_function, typer.substitutions)))
      // Type is always! OK at this level
      let expression = #(meta(Ok(expected)), e.Call(function, with))
      #(expression, typer)
    }
    e.Case(value, branches) -> {
      let #(branches, #(typer, _)) =
        misc.map_state(
          branches,
          #(typer, 1),
          fn(branch, state) {
            let #(typer, i) = state
            let #(name, pattern, then) = branch
            // variant value type
            let #(type_, bound_variables, typer) = pattern_type(pattern, typer)
            let row = #(name, type_)
            let state = #(typer, i + 1)
            // I think these need generalising after the value has been unified
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
            let inference = #(name, pattern, then, child(child(scope, i), 2))
            #(#(row, inference), state)
          },
        )
      let #(rows, inferences) = list.unzip(branches)
      let expected_value = t.Union(rows, None)
      // unifys value with patterns
      let #(value, typer) =
        infer(value, expected_value, effects, #(typer, child(scope, 0)))

      // let effects = t.resolve(effects, typer.substitutions)
      // Case could fail if not a union type at all ?
      let #(branches, typer) =
        misc.map_state(
          inferences,
          typer,
          fn(inf, typer) {
            let #(name, pattern, then, scope) = inf
            let #(then, typer) = infer(then, expected,effects, #(typer, scope))
            // TODO move resolving effects to the bottom
            // let effects = t.resolve(effects, typer.substitutions)

            let branch = #(name, pattern, then)
            #(branch, typer)
          },
        )
      let expression = #(meta(Ok(expected)), e.Case(value, branches))
      #(expression, typer)
    }
    // Type of provider is nil but actually it's dynamic because we just scrub the type information
    e.Hole -> {
      let typer =
        Typer(
          ..typer,
          inconsistencies: [
            #(scope.path, Warning("todo: implementation missing")),
            ..typer.inconsistencies
          ],
        )
      let expression = #(meta(Ok(expected)), e.Hole)
      #(expression, typer)
    }

    e.Provider(config, generator, _) -> {
      let expression = #(
        meta(Ok(expected)),
        e.Provider(config, generator, dynamic.from(Nil)),
      )
      #(expression, typer)
    }
  }
}

// body index needed for handling case branches
// Expected is a function that includes the effect types
// can be open or closed none Don't need to pass in effects here
fn infer_function(pattern, body, expected, typer, scope, body_index) {
  // Needs a typed function unit with correct meta data to come out
  let #(arg_type, bound_variables, typer) = pattern_type(pattern, typer)
  let #(y, typer) = next_unbound(typer)
  let return_type = t.Unbound(y)
  let #(z, typer) = next_unbound(typer)
  let effects = t.Unbound(z)
  let given = t.Function(arg_type, return_type, effects)
  let #(type_, typer) = try_unify(expected, given, typer, scope.path)

  // let effects = t.resolve(effects, typer.substitutions)
  
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
  let #(body, typer) =
    infer(body, return_type, effects, #(typer, child(scope, body_index)))
  #(body, typer, type_)
}
