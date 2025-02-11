import eyg/analysis/inference
import eyg/analysis/typ as t
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eygir/annotated as a
import gleam/dict
import gleeunit/should
import harness/stdlib

pub fn add_test() {
  let key = "int_add"
  let prog = a.apply(a.apply(a.builtin(key), a.integer(1)), a.integer(2))

  let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Integer))

  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Integer(3)))
}
