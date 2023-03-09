import gleam/mapx
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/integer
import harness/ffi/env
import eyg/analysis/inference
import eygir/expression as e
import gleeunit/should

pub fn add_test() {
  let key = "int_add"
  let prog = e.Apply(e.Apply(e.Builtin(key), e.Integer(1)), e.Integer(2))

  //   let sub = inference.infer(types, prog, t.Unbound(-1), t.Open(-2))
  //   inference.type_of(sub, [])
  //   |> should.equal(Ok(t.Integer))
  r.eval(prog, r.Env([], mapx.singleton(key, integer.add())), r.Value)
  |> should.equal(r.Value(r.Integer(3)))
}
