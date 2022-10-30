import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None, Some}
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype as t
import eyg/interpreter/interpreter as r
import eyg/typer

fn add_substitution(i, type_, substitutions) {
  case t.resolve(type_, substitutions) {
    t.Unbound(j) if j == i -> substitutions
    resolved -> [#(i, type_), ..substitutions]
  }
}

fn unify(a, b, substitutions, next) {
  case t.resolve(a, substitutions), t.resolve(b, substitutions) {
    t.Unbound(i), t.Unbound(j) if i == j -> #(substitutions, next)
    t.Unbound(i), type_ -> #(add_substitution(i, type_, substitutions), next)
    type_, t.Unbound(i) -> #(add_substitution(i, type_, substitutions), next)
    t.Record(row1, extra1), t.Record(row2, extra2) -> {
      let #(unmatched1, unmatched2, shared) = typer.group_shared(row1, row2)
      let join = next
      let next = next + 1
      let substitutions = case extra1 {
        Some(i) ->
          add_substitution(i, t.Record(unmatched2, Some(join)), substitutions)
        // Error(UnexpectedFields(only))
        None -> todo("how do we error out")
      }
      let substitutions = case extra2 {
        Some(i) ->
          add_substitution(i, t.Record(unmatched1, Some(join)), substitutions)
        // Error(UnexpectedFields(only))
        None -> todo("how do we error out")
      }
      list.fold(
        shared,
        #(substitutions, next),
        fn(state, pair) {
          let #(substitutions, next) = state
          let #(a, b) = pair
          unify(a, b, substitutions, next)
        },
      )
    }
    t.Tuple([]), t.Tuple([]) -> #(substitutions, next)
    a, b -> {
      io.debug(#(a, b))
      todo("Something not unified")
    }
  }
  //   list.try_fold(shared, #(state, seen), do_unify)
}

// TODO add substitute and unify row should be extracted and reused

fn assignments(pattern, next) {
  case pattern {
    p.Variable("") -> #([], next)
    p.Variable(label) -> #([#(label, t.Unbound(next))], next + 1)
    p.Tuple(elements) ->
      list.fold(
        elements,
        #([], next),
        fn(state, label) {
          let #(assigned, next) = state
          #([#(label, t.Unbound(next)), ..assigned], next + 1)
        },
      )
    p.Record(fields) ->
      list.fold(
        fields,
        #([], next),
        fn(state, field) {
          let #(assigned, next) = state
          let #(_key, label) = field
          #([#(label, t.Unbound(next)), ..assigned], next + 1)
        },
      )
  }
}

// We use unit type as everything
fn do_shake(
  source: e.Expression(Dynamic, Dynamic),
  expected: t.Monotype,
  substitutions: List(#(Int, t.Monotype)),
  env: t.Monotype,
  next: Int,
) {
  let #(_, expression) = source

  case expression {
    e.Binary(_) -> #(substitutions, next)
    e.Tuple(elements) ->
      list.fold(
        elements,
        #(substitutions, next),
        fn(state, element) {
          let #(substitutions, next) = state
          do_shake(element, t.Unbound(next), substitutions, env, next + 1)
        },
      )
    e.Record(fields) ->
      list.fold(
        fields,
        #(substitutions, next),
        fn(state, field) {
          let #(_, value) = field
          let #(substitutions, next) = state
          do_shake(value, t.Unbound(next), substitutions, env, next + 1)
        },
      )
    e.Access(value, key) -> {
      let record_type = t.Record([#(key, expected)], Some(next))
      let next = next + 1
      do_shake(value, record_type, substitutions, env, next)
    }
    e.Tagged(_, value) -> do_shake(value, t.Tuple([]), substitutions, env, next)
    e.Let(p.Variable(label), #(_, e.Function(pattern, body)), then) -> {
      // body
      let #(assigned, next) = assignments(pattern, next)
      let join = next
      let next = next + 1
      let assigned = [#(label, t.Tuple([])), ..assigned]
      let inner = t.Record(assigned, Some(join))
      let #(substitutions, next) =
        unify(t.Unbound(join), env, substitutions, next)
      let #(substitutions, next) =
        do_shake(body, expected, substitutions, inner, next)
      // then
      let join = next
      let next = next + 1
      let then_env = t.Record([#(label, t.Tuple([]))], Some(join))
      let #(substitutions, next) =
        unify(t.Unbound(join), env, substitutions, next)
      do_shake(then, t.Tuple([]), substitutions, then_env, next)
    }
    e.Let(pattern, value, then) -> {
      let #(substitutions, next) =
        do_shake(value, t.Unbound(next), substitutions, env, next + 1)
      let #(assigned, next) = assignments(pattern, next)
      let join = next
      let inner = t.Record(assigned, Some(join))
      let next = next + 1
      let #(substitutions, next) =
        unify(t.Unbound(join), env, substitutions, next)
      do_shake(then, t.Tuple([]), substitutions, inner, next)
    }
    e.Function(pattern, body) -> {
      let #(assigned, next) = assignments(pattern, next)
      let join = next
      let inner = t.Record(assigned, Some(join))
      let next = next + 1
      let #(substitutions, next) =
        unify(t.Unbound(join), env, substitutions, next)
      do_shake(body, expected, substitutions, inner, next)
    }
    e.Case(value, branches) -> {
      let #(substitutions, next) =
        do_shake(value, t.Unbound(next), substitutions, env, next + 1)
      list.fold(
        branches,
        #(substitutions, next),
        fn(state, branch) {
          let #(_, pattern, value) = branch
          let #(substitutions, next) = state
          let #(assigned, next) = assignments(pattern, next)
          let join = next
          let inner = t.Record(assigned, Some(join))
          let next = next + 1
          let #(substitutions, next) =
            unify(t.Unbound(join), env, substitutions, next)
          do_shake(value, t.Tuple([]), substitutions, inner, next)
        },
      )
    }
    e.Variable(label) -> {
      let needed = t.Record([#(label, expected)], Some(next))
      let next = next + 1
      unify(env, needed, substitutions, next)
    }
    // t.Record([#(label, t.Tuple([]))], None)
    e.Call(func, arg) -> {
      let #(substitutions, next) =
        do_shake(func, t.Tuple([]), substitutions, env, next)
      do_shake(arg, t.Unbound(next), substitutions, env, next + 1)
    }
    e.Hole -> #(substitutions, next)
    e.Provider(_, _, x) ->
      // todo("Provider should not be present in ast expansion should already have run")
      // TODO fix this we need to pass types more cleverly
      do_shake(dynamic.unsafe_coerce(x), expected, substitutions, env, next)
  }
}

pub fn shake(source, expected) {
  let outer = t.Record([], Some(0))
  let #(substitutions, next) = do_shake(source, expected, [], outer, 1)
  t.resolve(outer, substitutions)
}

pub fn shake_env(has, needed) {
  case needed, has {
    t.Record(pick, _), r.Record(env) -> {
      let fields =
        list.fold(
          pick,
          [],
          fn(picked, pick) {
            let #(label, type_) = pick
            case list.key_find(env, label) {
              Ok(term) -> {
                let inner = shake_env(term, type_)
                [#(label, inner), ..picked]
              }
              Error(Nil) -> {
                // TODO needs recursion
                io.debug("missing label")
                io.debug(label)
                picked
              }
            }
          },
        )
      r.Record(fields)
    }
    _, _ -> has
  }
}

pub fn shake_function(pattern, body, captured, self) {
  let func = e.function(pattern, body)
  let source = case self {
    Some(label) -> e.let_(p.Variable(label), func, e.variable(label))
    None -> func
  }

  let needed = shake(source, t.Tuple([]))
  shake_env(r.Record(map.to_list(captured)), needed)
}
