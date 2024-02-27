import gleam/dict
import eygir/expression as e
import eygir/annotated as e2
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import harness/stdlib
import gleeunit/should

pub fn string_append_test() {
  let key = "string_append"
  let source = e.Apply(e.Apply(e.Builtin(key), e.Str("fizz")), e.Str("buzz"))

  let source = e2.add_meta(source, Nil)
  r.execute(source, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Str("fizzbuzz")))
}
