import gleam/map
import gleam/option.{None}
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import eyg/analysis/inference
import eygir/expression as e
import harness/stdlib
import gleeunit/should

pub fn add_test() {
  let key = "int_add"
  let prog = e.Apply(e.Apply(e.Builtin(key), e.Integer(1)), e.Integer(2))

  let sub = inference.infer(map.new(), prog, t.Unbound(-1), t.Open(-2))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Integer))

  r.eval(prog, stdlib.env(), None)
  |> should.equal(r.Value(r.Integer(3)))
}
