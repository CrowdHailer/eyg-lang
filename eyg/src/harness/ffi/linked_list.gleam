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

fn do_pop(term, _builtins, k) {
  use elements <- cast.list(term)
  let return = case elements {
    [] -> r.error(r.unit)
    [head, ..tail] ->
      r.ok(r.Record([#("head", head), #("tail", r.LinkedList(tail))]))
  }
  r.continue(k, return)
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

pub fn fold_impl(list, initial, func, builtins, k) {
  use elements <- cast.list(list)
  do_fold(elements, initial, func, builtins, k)
}

pub fn do_fold(elements, state, f, builtins, k) {
  case elements {
    [] -> r.continue(k, state)
    [e, ..rest] ->
      r.eval_call(
        f,
        e,
        builtins,
        r.eval_call(_, state, builtins, do_fold(rest, _, f, builtins, k)),
      )
  }
}
