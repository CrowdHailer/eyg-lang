import gleam/result
import eyg/analysis/typ as t
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eyg/runtime/cast

pub fn pop() {
  let parts =
    t.Record(t.Extend(
      "head",
      t.Unbound(0),
      t.Extend("tail", t.LinkedList(t.Unbound(0)), t.Closed),
    ))
  let type_ =
    t.Fun(t.LinkedList(t.Unbound(0)), t.Open(1), t.result(parts, t.unit))
  #(type_, state.Arity1(do_pop))
}

fn do_pop(term, rev, env, k) {
  use elements <- result.then(cast.as_list(term))
  let return = case elements {
    [] -> v.error(v.unit)
    [head, ..tail] ->
      v.ok(v.Record([#("head", head), #("tail", v.LinkedList(tail))]))
  }
  Ok(#(state.V(return), rev, env, k))
}

pub fn fold() {
  let type_ =
    t.Fun(
      t.LinkedList(t.Unbound(-7)),
      t.Open(-8),
      t.Fun(
        t.Unbound(-9),
        t.Open(-10),
        t.Fun(
          t.Fun(
            t.Unbound(-7),
            t.Open(-11),
            t.Fun(t.Unbound(-9), t.Open(-12), t.Unbound(-9)),
          ),
          t.Open(-13),
          t.Unbound(-9),
        ),
      ),
    )
  #(type_, state.Arity3(fold_impl))
}

pub fn fold_impl(list, initial, func, rev, env, k) {
  use elements <- result.then(cast.as_list(list))
  do_fold(elements, initial, func, rev, env, k)
}

pub fn do_fold(elements, state, f, rev, env, k) {
  case elements {
    [] -> Ok(#(state.V(state), rev, env, k))
    [element, ..rest] -> {
      state.call(
        f,
        element,
        rev,
        env,
        state.Stack(
          state.CallWith(state, rev, env),
          state.Stack(
            state.Apply(
              v.Partial(v.Builtin("list_fold"), [v.LinkedList(rest)]),
              rev,
              env,
            ),
            state.Stack(state.CallWith(f, rev, env), k),
          ),
        ),
      )
    }
  }
}
