import gleam/io
import eygir/expression as e
import eyg/runtime/interpreter as r
import entry
import gleeunit/should

// Probably this belongs in something like
// harness/cli
pub fn concat_test() {
  let list =
    e.Apply(
      e.Apply(e.Cons, e.Binary("fizz")),
      e.Apply(e.Apply(e.Cons, e.Binary("buzz")), e.Tail),
    )
  let source = e.Apply(e.Variable("string_concat"), list)
  r.eval(source, entry.env_values(), r.Value)
  |> should.equal(r.Value(r.Binary("fizzbuzz")))
}
