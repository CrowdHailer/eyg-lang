import gleam/result
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
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
  #(type_, r.Arity1(do_pop))
}

fn do_pop(term, rev, env, k) {
  use elements <- result.then(cast.as_list(term))
  let return = case elements {
    [] -> v.error(v.unit)
    [head, ..tail] ->
      v.ok(v.Record([#("head", head), #("tail", v.LinkedList(tail))]))
  }
  Ok(#(r.V(return), rev, env, k))
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
  #(type_, r.Arity3(fold_impl))
}

pub fn fold_impl(list, initial, func, rev, env, k) {
  use elements <- result.then(cast.as_list(list))
  do_fold(elements, initial, func, rev, env, k)
}

pub fn do_fold(elements, state, f, rev, env, k) {
  case elements {
    [] -> Ok(#(r.V(state), rev, env, k))
    [element, ..rest] -> {
      r.step_call(
        f,
        element,
        rev,
        env,
        r.Stack(
          r.CallWith(state, rev, env),
          r.Stack(
            r.Apply(
              v.Partial(v.Builtin("list_fold"), [v.LinkedList(rest)]),
              rev,
              env,
            ),
            r.Stack(r.CallWith(f, rev, env), k),
          ),
        ),
      )
    }
  }
}
