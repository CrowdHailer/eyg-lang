import eyg/analysis/typ as t
import eyg/interpreter/builtin
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/result

pub fn pop() {
  let parts =
    t.Record(t.Extend(
      "head",
      t.Unbound(0),
      t.Extend("tail", t.LinkedList(t.Unbound(0)), t.Closed),
    ))
  let type_ =
    t.Fun(t.LinkedList(t.Unbound(0)), t.Open(1), t.result(parts, t.unit))
  #(type_, builtin.list_pop)
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
  #(type_, builtin.list_fold)
}

pub fn uncons() {
  let type_ = t.unit
  #(type_, state.Arity3(do_uncons))
}

fn do_uncons(list, empty, nonempty, meta, env, k) {
  use elements <- result.then(cast.as_list(list))

  case elements {
    [] -> state.call(empty, v.unit(), meta, env, k)
    [head, ..tail] -> {
      let k = state.Stack(state.CallWith(v.LinkedList(tail), env), meta, k)
      state.call(nonempty, head, meta, env, k)
    }
  }
}
