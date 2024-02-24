import gleam/dict
import eygir/expression as e
import eygir/annotated as e2
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
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
  let source = e2.add_meta(source, Nil)

  r.execute(source, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Str("initialfizzbuzz")))
}
