import gleam/option.{None}
import eygir/expression as e
import eyg/runtime/interpreter as r
import harness/stdlib
import gleeunit/should

pub fn fold_test() {
  let list =
    e.Apply(
      e.Apply(e.Cons, e.Str("fizz")),
      e.Apply(e.Apply(e.Cons, e.Str("buzz")), e.Tail),
    )
  let reducer =
    e.Lambda(
      "element",
      e.Lambda(
        "state",
        e.Apply(
          e.Apply(e.Builtin("string_append"), e.Variable("state")),
          e.Variable("element"),
        ),
      ),
    )
  let source =
    e.Apply(
      e.Apply(e.Apply(e.Builtin("list_fold"), list), e.Str("initial")),
      reducer,
    )
  r.eval(source, stdlib.env(), None)
  |> should.equal(r.Value(r.Str("initialfizzbuzz")))
}
