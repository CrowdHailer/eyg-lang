import eygir/expression as e
import eyg/runtime/interpreter as r
import harness/stdlib
import gleeunit/should

pub fn string_append_test() {
  let key = "string_append"
  let source =
    e.Apply(e.Apply(e.Builtin(key), e.Binary("fizz")), e.Binary("buzz"))
  r.eval(source, stdlib.env(), r.Value)
  |> should.equal(r.Value(r.Binary("fizzbuzz")))
}
