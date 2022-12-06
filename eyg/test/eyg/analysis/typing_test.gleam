import gleam/io
import eyg/analysis/expression as e
import eyg/analysis/typ as t
import eyg/analysis/infer.{infer}
// top level analysis
import eyg/analysis/unification.{resolve}
import gleam/javascript

// Primitive
pub fn binary_test() {
  let exp = e.Binary
  let env = infer.empty_env()
  let typ = t.Binary
  let eff = t.RowClosed
  let ref = javascript.make_reference(0)

  let _ = infer(env, exp, typ, eff, ref)

  let typ = t.Var(1)
  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Binary = resolve(sub, typ)
}

pub fn integer_test() {
  let exp = e.Integer
  let env = infer.empty_env()
  let typ = t.Integer
  let eff = t.RowClosed
  let ref = javascript.make_reference(0)

  let _ = infer(env, exp, typ, eff, ref)

  let typ = t.Var(1)
  let ref = javascript.make_reference(0)

  let sub = infer(env, exp, typ, eff, ref)
  assert t.Integer = resolve(sub, typ)
}

// Variables
pub fn variables_test() {
  let exp = e.Let("x", e.Binary, e.Variable("x"))
  let env = infer.empty_env()
  let typ = t.Binary
  let eff = t.RowClosed
  let ref = javascript.make_reference(0)

  let _ = infer(env, exp, typ, eff, ref)

  let typ = t.Var(1)
  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Binary = resolve(sub, typ)
}
