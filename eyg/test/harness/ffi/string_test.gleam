import eyg/ir/tree as ir
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import gleam/dict
import gleeunit/should
import harness/stdlib

pub fn string_append_test() {
  let key = "string_append"
  let source =
    ir.apply(ir.apply(ir.builtin(key), ir.string("fizz")), ir.string("buzz"))

  r.execute(source, stdlib.env(), dict.new())
  |> should.equal(Ok(v.String("fizzbuzz")))
}
