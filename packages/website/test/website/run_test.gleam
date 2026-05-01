import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/crypto
import gleam/http/request
import gleam/http/response
import multiformats/cid/v1
import touch_grass/http
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
  let assert #(run.Suspended(0, env:, k:), updated, [effect]) =
    execute(source, initial)
  assert 1 == updated.counter

  let assert browser.Spotless(harness.DNSimple, resume:) = effect
  let assert SpotlessConnectCompleted(service, result) = resume(Ok("dns_tok"))
  let #(updated, effects) = run.connect_completed(updated, service, result)
  let assert [] = updated.tasks
  let assert [browser.Fetch(request:, resume:)] = effects
  assert "/v2/accounts" == request.path
  assert "api.dnsimple.com" == request.host
  assert Ok("Bearer dns_tok") == request.get_header(request, "authorization")

  let assert EffectHandled(0, value) =
    resume(Ok(response.new(200) |> response.set_body(<<>>)))

  assert 1 == updated.counter
  let ok_response =
    v.ok(http.response_to_eyg(response.new(200) |> response.set_body(<<>>)))
  let assert #(run.Concluded(value), updated, []) =
    continue(value, env, k, updated)
  assert ok_response == value
  // running again will have token in context
  let assert #(run.Suspended(1, env:, k:), updated, [effect]) =
    execute(source, updated)
  assert 2 == updated.counter

  let assert browser.Fetch(request:, resume:) = effect
  assert "/v2/accounts" == request.path
  assert "api.dnsimple.com" == request.host
  assert Ok("Bearer dns_tok") == request.get_header(request, "authorization")
  let assert EffectHandled(1, value) =
    resume(Ok(response.new(200) |> response.set_body(<<>>)))
  let assert #(run.Concluded(value), _updated, []) =
    continue(value, env, k, updated)
  assert ok_response == value
}

pub fn valid_reference_test() {
  let lib = ir.record([#("count", ir.integer(43))])
  let cid = cid_from_tree(lib)

  let source = ir.get(ir.reference(cid), "count")
  let initial = context()
  let assert #(run.Suspended(0, env:, k:), updated, [effect]) =
    execute(source, initial)
  assert 1 == updated.counter
  let assert browser.Fetch(request:, resume:) = effect
  assert "/modules/" <> v1.to_string(cid) == request.path
  let assert ModuleLookupCompleted(cid, result) =
    resume(Ok(module_response(lib)))

  let #(updated, done, effects) = run.get_module_completed(updated, cid, result)
  let assert [#(0, mod)] = done
  assert [] == updated.tasks
  assert [] == effects
  let assert #(run.Concluded(value), _updated, []) =
    continue(mod, env, k, updated)
  assert v.Integer(43) == value
}

fn cid_from_tree(source) {
  let cid.Sha256(bytes:, resume:) = cid.from_tree(source)
  resume(crypto.hash(crypto.Sha256, bytes))
}

fn module_response(source) {
  let body = dag_json.to_block(source)
  response.new(200)
  |> response.set_body(body)
}
