import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/http/request
import gleam/http/response
import multiformats/cid/v1
import website/harness/browser
import website/harness/harness
import website/run

pub type Message {
  EffectHandled(task_id: Int, value: run.Value)
  SpotlessConnectCompleted(harness.Service, Result(String, String))
  ModuleLookupCompleted(v1.Cid, Result(ir.Node(Nil), String))
}

fn context() {
  run.empty(EffectHandled, SpotlessConnectCompleted, ModuleLookupCompleted)
}

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
  let initial = context()
  let assert #(run.Concluded(value), updated, []) = execute(source, initial)
  assert v.Integer(3) == value
  assert initial == updated
}

pub fn synchronous_effect_test() {
  let source = ir.call(ir.perform("Random"), [ir.integer(1)])
  let initial = context()
  let assert #(run.Concluded(value), updated, []) = execute(source, initial)
  assert v.Integer(0) == value
  assert initial == updated
}

pub fn asynchronous_effect_test() {
  let source = ir.call(ir.perform("Alert"), [ir.string("hi")])
  let initial = context()
  let assert #(run.Suspended(0, env:, k:), updated, [task]) =
    execute(source, initial)
  assert 1 == updated.counter
  let assert browser.Alert("hi", resume:) = task
  let assert EffectHandled(0, value) = resume()
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
  let initial = context()
  let assert #(run.Suspended(0, env:, k:), updated, [task]) =
    execute(source, initial)
  assert 1 == updated.counter

  let assert browser.Spotless(harness.DNSimple, resume:) = task
  let assert SpotlessConnectCompleted(service, result) = resume(Ok("dns_tok"))
  let #(updated, effects) = run.connect_completed(updated, service, result)
  let assert [] = updated.tasks
  let assert [browser.Fetch(request:, resume:)] = effects
  echo request
  // TODO check origin
  let assert EffectHandled(0, value) =
    resume(Ok(response.new(200) |> response.set_body(<<>>)))
  echo value
  assert 1 == updated.counter
  let assert #(run.Concluded(value), _, []) = continue(value, env, k, updated)
  echo value
  // let assert #(run.Suspended(1, run.Effect, env:, k:), updated, [task]) =
  //   continue(, env, k, context)
  // let assert #(run.Concluded(value), _, []) = continue(value, env, k, updated)
  // assert v.unit() == value
}
