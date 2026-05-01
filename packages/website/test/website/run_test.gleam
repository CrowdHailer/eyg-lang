import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import touch_grass/http
import website/harness/browser
import website/harness/harness
import website/run

fn execute(source, context) {
  source
  |> ir.map_annotation(fn(_) { [] })
  |> expression.execute([])
  |> run.loop(context)
}

fn continue(value, env, k, context) {
  expression.resume(value, env, k)
  |> run.loop(context)
}

pub fn pure_program_test() {
  let source = ir.add(ir.integer(1), ir.integer(2))
  let context = run.empty()
  let assert #(run.Concluded(value), updated, []) = execute(source, context)
  assert v.Integer(3) == value
  assert context == updated
}

pub fn synchronous_effect_test() {
  let source = ir.call(ir.perform("Random"), [ir.integer(1)])
  let context = run.empty()
  let assert #(run.Concluded(value), updated, []) = execute(source, context)
  assert v.Integer(0) == value
  assert context == updated
}

pub fn asynchronous_effect_test() {
  let source = ir.call(ir.perform("Alert"), [ir.string("hi")])
  let context = run.empty()
  let assert #(run.Suspended(0, run.Effect, env:, k:), updated, [task]) =
    execute(source, context)
  assert 1 == updated.counter
  let assert browser.Alert("hi", resume:) = task
  let assert run.Handled(0, value) = resume()
  let assert #(run.Concluded(value), _, []) = continue(value, env, k, updated)
  assert v.unit() == value
}

pub fn spotless_effect_test() {
  let operation =
    ir.record([
      #("method", ir.tagged("GET", ir.unit())),
      #("path", ir.string("/v2/accounts")),
      #("query", ir.tagged("None", ir.unit())),
      #("headers", ir.tail()),
      #("body", ir.binary(<<>>)),
    ])
  let source = ir.call(ir.perform("DNSimple"), [operation])
  let context = run.empty()
  let assert #(run.Suspended(0, run.Connect(s, op), env:, k:), updated, [task]) =
    execute(source, context)
  assert 1 == updated.counter
  assert harness.DNSimple == s
  assert "/v2/accounts" == op.path
  let assert browser.Spotless(harness.DNSimple, resume:) = task
  let assert run.SpotlessConnectCompleted(_result) = resume(Ok("dns_tok"))
  // let assert #(run.Suspended(1, run.Effect, env:, k:), updated, [task]) =
  //   continue(, env, k, context)
  // let assert #(run.Concluded(value), _, []) = continue(value, env, k, updated)
  // assert v.unit() == value
}
