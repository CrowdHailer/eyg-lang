import eygir/expression as e
import eyg/runtime/interpreter as r
import harness/ffi/string
import harness/stdlib
import gleeunit/should

pub fn string_append_test() {
  let var = "ffi_append"
  let source =
    e.Apply(e.Apply(e.Variable(var), e.Binary("fizz")), e.Binary("buzz"))
  r.eval(source, [#(var, string.append().1)], r.Value)
  |> should.equal(r.Value(r.Binary("fizzbuzz")))
}

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
  r.eval(source, stdlib.lib().1, r.Value)
  |> should.equal(r.Value(r.Binary("initialfizzbuzz")))
}
