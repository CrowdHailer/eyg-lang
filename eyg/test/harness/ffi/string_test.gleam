import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eygir/annotated as a
import gleam/dict
import gleeunit/should
import harness/stdlib

pub fn string_append_test() {
  let key = "string_append"
  let source =
    a.apply(a.apply(a.builtin(key), a.string("fizz")), a.string("buzz"))

  r.execute(source, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Str("fizzbuzz")))
}
