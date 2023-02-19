import eygir/expression as e
import eyg/runtime/interpreter as r
import harness/stdlib
import gleeunit/should

pub fn fold_test() {
  let list =
    e.Apply(
      e.Apply(e.Cons, e.Binary("fizz")),
      e.Apply(e.Apply(e.Cons, e.Binary("buzz")), e.Tail),
    )
  let reducer =
    e.Lambda(
      "element",
      e.Lambda(
        "state",
        e.Apply(
          e.Apply(e.Variable("ffi_append"), e.Variable("state")),
          e.Variable("element"),
        ),
      ),
    )
  let source =
    e.Apply(
      e.Apply(e.Apply(e.Variable("ffi_fold"), list), e.Binary("initial")),
      reducer,
    )
  r.eval(source, stdlib.lib().1, fn(_, _) { todo("no linked list") }, r.Value)
  |> should.equal(r.Value(r.Binary("initialfizzbuzz")))
}
