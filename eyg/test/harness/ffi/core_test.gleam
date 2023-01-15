import eyg/analysis/typ as t
import eyg/analysis/inference
import eyg/runtime/interpreter as r
import eygir/expression as e
import harness/ffi/core
import harness/ffi/env
import gleeunit/should

pub fn unequal_test() {
  let #(types, values) =
    env.init()
    |> env.extend("equal", core.equal())

  let prog = e.Apply(e.Apply(e.Variable("equal"), e.Integer(1)), e.Integer(2))
  let sub = inference.infer(types, prog, t.Unbound(-1), t.Open(-2))

  inference.type_of(sub, [])
  |> should.equal(Ok(core.boolean))

  r.eval(prog, values, r.Value)
  |> should.equal(r.Value(core.false))
}


pub fn equal_test() {
  let #(types, values) =
    env.init()
    |> env.extend("equal", core.equal())

  let prog = e.Apply(e.Apply(e.Variable("equal"), e.Binary("foo")), e.Binary("foo"))
  let sub = inference.infer(types, prog, t.Unbound(-1), t.Open(-2))

  inference.type_of(sub, [])
  |> should.equal(Ok(core.boolean))

  r.eval(prog, values, r.Value)
  |> should.equal(r.Value(core.true))
}