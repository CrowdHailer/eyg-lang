import eyg/interpreter/expression as r
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/runtime/capture
import gleam/dict
import gleeunit/should
import harness/ffi/core.{expression_to_language}
import harness/stdlib

pub fn eval_test() {
  let value = ir.string("foo")

  let p =
    value
    |> expression_to_language()
    |> v.LinkedList()
    |> capture.capture(Nil)
  let prog = ir.apply(ir.builtin("eval"), p)
  // This is old style inference not JM
  // let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))

  // inference.sound(sub)
  // |> should.equal(Ok(Nil))

  // inference.type_of(sub, [])
  // |> should.equal(Ok(t.boolean))

  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Tagged("Ok", v.String("foo"))))
}

pub fn language_to_expression_test() {
  ir.apply(ir.variable("x"), ir.integer(1))
  |> core.expression_to_language()
  |> core.language_to_expression()
  |> should.be_ok
}
