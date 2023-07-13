import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/cast

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

fn do_pop(term, env, k) {
  use elements <- cast.require(cast.list(term), env, k)
  let return = case elements {
    [] -> r.error(r.unit)
    [head, ..tail] ->
      r.ok(r.Record([#("head", head), #("tail", r.LinkedList(tail))]))
  }
  r.prim(r.Value(return), env, k)
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

pub fn fold_impl(list, initial, func, env, k) {
  use elements <- cast.require(cast.list(list), env, k)
  do_fold(elements, initial, func, env, k)
}

pub fn do_fold(elements, state, f, env, k) {
  todo("do fold")
  // case elements {
  //   [] -> r.continue(k, state)
  //   [e, ..rest] ->
  //     r.eval_call(
  //       f,
  //       e,
  //       env,
  //       r.eval_call(_, state, env, do_fold(rest, _, f, env, k)),
  //     )
  // }
}
