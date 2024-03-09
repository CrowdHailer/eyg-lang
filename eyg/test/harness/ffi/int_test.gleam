import gleam/dict
import eyg/analysis/typ as t
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eyg/analysis/inference
import eygir/expression as e
import eygir/annotated as e2
import harness/stdlib
import gleeunit/should

pub fn add_test() {
  let key = "int_add"
  let prog = e.Apply(e.Apply(e.Builtin(key), e.Integer(1)), e.Integer(2))

  let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Integer))

  let prog = e2.add_annotation(prog, Nil)
  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Integer(3)))
}
