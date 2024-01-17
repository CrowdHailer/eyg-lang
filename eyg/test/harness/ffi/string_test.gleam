import gleam/dict
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/runtime/value as v
import harness/stdlib
import gleeunit/should

pub fn string_append_test() {
  let key = "string_append"
  let source = e.Apply(e.Apply(e.Builtin(key), e.Str("fizz")), e.Str("buzz"))
  r.eval(source, stdlib.env(), r.Empty(dict.new()))
  |> should.equal(Ok(v.Str("fizzbuzz")))
}
