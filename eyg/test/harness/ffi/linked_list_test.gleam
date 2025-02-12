import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eygir/annotated as a
import gleam/dict
import gleeunit/should
import harness/stdlib

pub fn fold_test() {
  let list =
    a.apply(
      a.apply(a.cons(), a.string("fizz")),
      a.apply(a.apply(a.cons(), a.string("buzz")), a.tail()),
    )
  let reducer =
    a.lambda(
      "element",
      a.lambda(
        "state",
        a.apply(
          a.apply(a.builtin("string_append"), a.variable("state")),
          a.variable("element"),
        ),
      ),
    )
  let source =
    a.apply(
      a.apply(a.apply(a.builtin("list_fold"), list), a.string("initial")),
      reducer,
    )

  r.execute(source, stdlib.env(), dict.new())
  |> should.equal(Ok(v.String("initialfizzbuzz")))
}
