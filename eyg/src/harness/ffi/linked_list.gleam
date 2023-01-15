import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/spec.{
  build, empty, end, field, lambda, list_of, record, unbound, union, variant,
}

pub fn pop() {
  let el = unbound()
  lambda(
    list_of(el),
    union(variant(
      "Ok",
      record(field("head", el, field("tail", list_of(el), empty()))),
      variant("Error", record(empty()), end()),
    )),
  )
  |> build(fn(list) {
    fn(ok) {
      fn(error) {
        case list {
          [head, ..tail] -> ok(#(head, #(tail, Nil)))
          [] -> error(Nil)
        }
      }
    }
  })
}

pub fn fold() {
  // let el = unbound()
  // let acc = unbound()
  // lambda(list_of(el), lambda(acc, lambda(la)))
  // TODO needs lambda in
  #(
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
    ),
    r.builtin3(fn(list, initial, f, k) {
      assert r.LinkedList(elements) = list
      do_fold(elements, initial, f, k)
    }),
  )
}

fn do_fold(elements, state, f, k) {
  case elements {
    [] -> r.continue(k, state)
    [e, ..rest] ->
      r.eval_call(f, e, r.eval_call(_, state, do_fold(rest, _, f, k)))
  }
}
