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

pub type Reason(n) {
  IncorrectArity(expected: Int, given: Int)
  UnknownVariable(label: String)
  UnmatchedTypes(expected: t.Monotype(n), given: t.Monotype(n))
  MissingFields(expected: List(#(String, t.Monotype(n))))
  UnexpectedFields(unexpected: List(#(String, t.Monotype(n))))
  UnableToProvide(expected: t.Monotype(n), generator: e.Generator)
  ProviderFailed(generator: e.Generator, expected: t.Monotype(n))
  Warning(message: String)
}

pub fn root_scope(variables) {
  Scope(variables: variables, path: [])
}

pub type Scope(n) {
  Scope(path: List(Int), variables: List(#(String, polytype.Polytype(n))))
}

pub fn child(scope, i) {
  let Scope(path: path, ..) = scope
  Scope(..scope, path: path.append(path, i))
}

pub type Typer(n) {
  Typer(
    native_to_string: fn(n) -> String,
    next_unbound: Int,
    substitutions: List(#(Int, t.Monotype(n))),
    inconsistencies: List(#(List(Int), Reason(n))),
  )
}

pub fn reason_to_string(reason, typer: Typer(n)) {
  case reason {
    IncorrectArity(expected, given) ->
      string.concat([
        "Incorrect Arity expected ",
        int.to_string(expected),
        " given ",
        int.to_string(given),
      ])
    UnknownVariable(label) ->
      string.concat(["Unknown variable: \"", label, "\""])
    UnmatchedTypes(expected, given) ->
      string.concat([
        "Unmatched types expected ",
        t.to_string(
          t.resolve(expected, typer.substitutions),
          typer.native_to_string,
        ),
        " given ",
        t.to_string(
          t.resolve(given, typer.substitutions),
          typer.native_to_string,
        ),
      ])
    MissingFields(expected) ->
      [
        "Missing fields: ",
        ..list.map(
          expected,
          fn(x) {
            let #(name, type_) = x
            string.concat([
              name,
              ": ",
              t.to_string(
                t.resolve(type_, typer.substitutions),
                typer.native_to_string,
              ),
            ])
          },
        )
        |> list.intersperse(", ")
      ]
      |> string.concat

    UnexpectedFields(expected) ->
      [
        "Unexpected fields: ",
        ..list.map(
          expected,
          fn(x) {
            let #(name, type_) = x
            string.concat([
              name,
              ": ",
              t.to_string(
                t.resolve(type_, typer.substitutions),
                typer.native_to_string,
              ),
            ])
          },
        )
        |> list.intersperse(", ")
      ]
      |> string.concat
    UnableToProvide(expected, g) ->
      string.concat([
        "Unable to generate for expected type ",
        t.to_string(
          t.resolve(expected, typer.substitutions),
          typer.native_to_string,
        ),
        " with generator ",
        e.generator_to_string(g),
      ])
    ProviderFailed(g, expected) ->
      string.concat([
        "Provider '",
        e.generator_to_string(g),
        "' unable to generate code for type: ",
        t.to_string(expected, typer.native_to_string),
      ])
    Warning(message) -> message
  }
}

// I think the types should be concerned only with types, no redering
pub fn init(native_to_string) {
  Typer(native_to_string, 0, [], [])
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

pub type Metadata(n) {
  Metadata(
    type_: Result(t.Monotype(n), Reason(n)),
    scope: List(#(String, polytype.Polytype(n))),
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
  tree: e.Expression(Metadata(n), a),
) -> Result(t.Monotype(n), Reason(n)) {
  let #(Metadata(type_: type_, ..), _) = tree
  type_
}

pub fn do_unify(
  state: #(Typer(n), List(Int)),
  pair: #(t.Monotype(n), t.Monotype(n)),
) -> Result(#(Typer(n), List(Int)), Reason(n)) {
  // io.debug("do_unify")
  let #(t1, t2) = pair
  let #(state, seen) = state
  // io.debug(t1)
  // io.debug(t2)
  // io.debug(state.substitutions)
  case t1, t2 {
    t.Unbound(i), t.Unbound(j) if i == j -> Ok(#(state, seen))
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
    t.Native(n1), t.Native(n2) if n1 == n2 -> Ok(#(state, seen))
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
        [], _ -> Ok(#(state, seen))
        only, Some(i) ->
          Ok(add_substitution(i, t.Union(only, Some(next)), #(state, seen)))
        only, None -> Error(UnexpectedFields(only))
      }
      try #(state, seen) = case unmatched1, extra2 {
        [], _ -> Ok(#(state, seen))
        only, Some(i) ->
          Ok(add_substitution(i, t.Union(only, Some(next)), #(state, seen)))
        only, None -> Error(MissingFields(only))
      }
      list.try_fold(shared, #(state, seen), do_unify)
    }
    t.Function(from1, to1), t.Function(from2, to2) -> {
      try #(state, seen) = do_unify(#(state, seen), #(from1, from2))
      do_unify(#(state, seen), #(to1, to2))
    }
    _, _ -> Error(UnmatchedTypes(t1, t2))
  }
}

fn add_substitution(
  i,
  type_,
  state: #(Typer(n), List(Int)),
) -> #(Typer(n), List(Int)) {
  let #(state, seen) = state
  let substitutions = [#(i, type_), ..state.substitutions]
  #(Typer(..state, substitutions: substitutions), seen)
}

pub fn unify(t1, t2, state: Typer(n)) {
  try #(state, seen) = do_unify(#(state, []), #(t1, t2))
  Ok(state)
}

fn with_unbound(thing: a, typer) -> #(#(a, t.Monotype(n)), Typer(n)) {
  let #(x, typer) = next_unbound(typer)
  let type_ = t.Unbound(x)
  #(#(thing, type_), typer)
}

fn fresh(typer) {
  let #(x, typer) = next_unbound(typer)
  let type_ = t.Unbound(x)
  #(type_, typer)
}

pub fn equal_fn() {
  polytype.Polytype(
    [1],
    t.Function(
      t.Tuple([t.Unbound(1), t.Unbound(1)]),
      t.Union([#("True", t.Tuple([])), #("False", t.Tuple([]))], None),
    ),
  )
}

// Make private and always put in infer?
pub fn expand_providers(tree, typer) {
  let #(meta, expression) = tree
  case expression {
    // Binary and Variable are unstructured and restructured to change type of provider generated content
    e.Binary(value) -> #(#(meta, e.Binary(value)), typer)
    e.Variable(value) -> #(#(meta, e.Variable(value)), typer)
    e.Tuple(elements) -> {
      let #(elements, typer) = misc.map_state(elements, typer, expand_providers)
      #(#(meta, e.Tuple(elements)), typer)
    }
    e.Record(fields) -> {
      let #(fields, typer) =
        misc.map_state(
          fields,
          typer,
          fn(field, typer) {
            let #(key, value) = field
            let #(value, typer) = expand_providers(value, typer)
            let field = #(key, value)
            #(field, typer)
          },
        )
      #(#(meta, e.Record(fields)), typer)
    }
    e.Tagged(tag, value) -> {
      let #(value, typer) = expand_providers(value, typer)
      #(#(meta, e.Tagged(tag, value)), typer)
    }
    e.Let(label, value, then) -> {
      let #(value, typer) = expand_providers(value, typer)
      let #(then, typer) = expand_providers(then, typer)
      #(#(meta, e.Let(label, value, then)), typer)
    }
    e.Function(from, to) -> {
      // let #(from, typer) = expand_providers(from, typer)
      let #(to, typer) = expand_providers(to, typer)
      #(#(meta, e.Function(from, to)), typer)
    }
    e.Call(func, with) -> {
      let #(func, typer) = expand_providers(func, typer)
      let #(with, typer) = expand_providers(with, typer)
      #(#(meta, e.Call(func, with)), typer)
    }
    e.Case(value, branches) -> {
      let #(value, typer) = expand_providers(value, typer)
      let #(branches, typer) =
        misc.map_state(
          branches,
          typer,
          fn(branch, typer) {
            let #(key, pattern, then) = branch
            let #(then, typer) = expand_providers(then, typer)
            let branch = #(key, pattern, then)
            #(branch, typer)
          },
        )
      #(#(meta, e.Case(value, branches)), typer)
    }

    // Hole needs to be separate, it can't be a function call because it is not always going to be a function that gets called.
    // TODO this loader exception lets it produce invalid code while experimenting
    e.Hole | e.Provider(_, e.Loader, _) -> #(#(meta, e.Hole), typer)
    e.Provider(config, g, _) -> {
      let Metadata(type_: Ok(expected), ..) = meta
      let Typer(substitutions: substitutions, ..) = typer
      let expected = t.resolve(expected, substitutions)
      case e.generate(g, config, expected) {
        Ok(tree) -> {
          let #(typed, typer) = infer(tree, expected, #(typer, root_scope([])))
          // expand_providers(typed, typer)
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
            infer(dummy, expected, #(typer, root_scope([])))
          let meta =
            Metadata(
              ..meta,
              type_: Error(UnableToProvide(expected: expected, generator: g)),
            )
          // expand_providers(typed, typer)
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

pub fn infer(
  expression: e.Expression(Dynamic, Dynamic),
  expected: t.Monotype(n),
  state: #(Typer(n), Scope(n)),
) -> #(e.Expression(Metadata(n), Dynamic), Typer(n)) {
  // return all context so more info can be added later
  // io.debug("infer")
  // io.debug(expression)
  // io.debug(expected)
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
              infer(element, expected, #(tz, child(scope, i)))
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
              infer(value, expected, #(tz, child(child(scope, i), 1)))
            #(#(name, value), #(tz, i + 1))
          },
        )
      let expression = #(meta(type_), e.Record(fields))
      #(expression, typer)
    }
    e.Tagged(tag, value) -> {
      let #(x, typer) = next_unbound(typer)
      let value_type = t.Unbound(x)
      let #(y, typer) = next_unbound(typer)
      let given = t.Union([#(tag, value_type)], Some(y))
      let #(type_, typer) = try_unify(expected, given, typer, scope.path)
      let #(value, typer) = infer(value, value_type, #(typer, child(scope, 1)))
      let expression = #(meta(type_), e.Tagged(tag, value))
      #(expression, typer)
    }
    e.Variable(label) -> {
      // Returns typer because of instantiation,
      // TODO separate lookup for instantiate, good for let rec
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
          let self_type = t.Function(arg_type, return_type)
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
          let scope = set_variable(#(label, self_type), typer, scope)
          #(#(meta(type_), e.Function(pattern, body)), #(typer, scope))
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
      // There are ALOT more type variables if handling all the errors.
      let #(body, typer, type_) =
        infer_function(pattern, body, expected, typer, scope, 1)
      #(#(meta(type_), e.Function(pattern, body)), typer)
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
        infer(value, expected_value, #(typer, child(scope, 0)))
      // Case could fail if not a union type at all ?
      let #(branches, typer) =
        misc.map_state(
          inferences,
          typer,
          fn(inf, typer) {
            let #(name, pattern, then, scope) = inf
            let #(then, typer) = infer(then, expected, #(typer, scope))
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
fn infer_function(pattern, body, expected, typer, scope, body_index) {
  // Needs a typed function unit with correct meta data to come out
  let #(arg_type, bound_variables, typer) = pattern_type(pattern, typer)
  let #(y, typer) = next_unbound(typer)
  let return_type = t.Unbound(y)
  let given = t.Function(arg_type, return_type)
  let #(type_, typer) = try_unify(expected, given, typer, scope.path)
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
    infer(body, return_type, #(typer, child(scope, body_index)))
  #(body, typer, type_)
}
