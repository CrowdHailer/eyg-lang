import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/spec.{
  build, empty, end, lambda, record, string, unbound, union, variant,
}

pub const true = r.Tagged("True", r.Record([]))

pub const false = r.Tagged("False", r.Record([]))

pub fn equal() {
  let el = unbound()
  lambda(
    el,
    lambda(
      el,
      union(variant(
        "True",
        record(empty()),
        variant("False", record(empty()), end()),
      )),
    ),
  )
  |> build(fn(x) {
    fn(y) {
      fn(true) {
        fn(false) {
          case x == y {
            True -> true(Nil)
            False -> false(Nil)
          }
        }
      }
    }
  })
}

pub fn debug() {
  lambda(unbound(), string())
  |> build(r.to_string)
}

fn fixed(builder) {
  r.Builtin(fn(arg, inner_k) {
    r.eval_call(builder, fixed(builder), r.eval_call(_, arg, inner_k))
  })
}

pub fn fix() {
  let typ =
    t.Fun(
      t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-1)),
      t.Open(-3),
      t.Unbound(-1),
    )

  let value =
    r.Builtin(fn(builder, k) { r.eval_call(builder, fixed(builder), k) })
  #(typ, value)
}
