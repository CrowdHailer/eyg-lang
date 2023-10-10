import gleam/option.{None}
import eygir/expression as e
import eyg/runtime/interpreter as r
import harness/stdlib
import gleeunit/should

pub fn string_append_test() {
  let key = "string_append"
  let source = e.Apply(e.Apply(e.Builtin(key), e.Str("fizz")), e.Str("buzz"))
  r.eval(source, stdlib.env(), None)
  |> should.equal(r.Value(r.Str("fizzbuzz")))
}
