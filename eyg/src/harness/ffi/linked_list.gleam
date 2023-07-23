import gleam/option.{Some}
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

fn do_pop(term, rev, env, k) {
  use elements <- cast.require(cast.list(term), rev, env, k)
  let return = case elements {
    [] -> r.error(r.unit)
    [head, ..tail] ->
      r.ok(r.Record([#("head", head), #("tail", r.LinkedList(tail))]))
  }
  r.prim(r.Value(return), rev, env, k)
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
  use elements <- cast.require(cast.list(list), rev, env, k)
  do_fold(elements, initial, func, rev, env, k)
}

pub fn do_fold(elements, state, f, rev, env, k) {
  case elements {
    [] -> r.prim(r.Value(state), rev, env, k)
    [element, ..rest] -> {
      r.step_call(
        f,
        element,
        rev,
        env,
        Some(r.Kont(
          r.CallWith(state, rev, env),
          Some(r.Kont(
            r.Apply(
              r.Defunc(r.Builtin("list_fold"), [r.LinkedList(rest)]),
              rev,
              env,
            ),
            Some(r.Kont(r.CallWith(f, rev, env), k)),
          )),
        )),
      )
    }
  }
}
