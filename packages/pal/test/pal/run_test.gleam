import dag_json as codec
import eyg/hub/cache
import eyg/hub/publisher
import eyg/hub/release
import eyg/hub/schema
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/option.{None}
import multiformats/cid/v1
import multiformats/hashes
import ogre/origin
import pal/browser
import spotless/oauth_2_1/token
import touch_grass/harness/browser as harness
import touch_grass/http
import untethered/ledger/schema as ledger_schema

pub type Message {
  EffectHandled(task_id: Int, value: run.Value)
  SpotlessConnectCompleted(harness.Service, Result(token.Response, String))
  ModuleLookupCompleted(v1.Cid, Result(ir.Node(Nil), String))
  PullPackagesCompleted(Result(List(schema.ArchivedEntry), String))
}

fn empty_context() {
  run.empty(
    origin.https("eyg.test"),
    EffectHandled,
    SpotlessConnectCompleted,
    ModuleLookupCompleted,
    PullPackagesCompleted,
  )
}

fn execute(source, context) {
  source
  |> ir.map_annotation(fn(_) { [] })
  |> expression.execute([])
  |> run.loop(context, expression.resume)
}

fn continue(value, env, k, context) {
  expression.resume(value, env, k)
  |> run.loop(context, expression.resume)
}

pub fn pure_program_test() {
  let source = ir.add(ir.integer(1), ir.integer(2))
  let initial = empty_context()
  let assert #(run.Concluded(value), updated, []) = execute(source, initial)
  assert v.Integer(3) == value
  assert initial == updated
}

pub fn synchronous_effect_test() {
  let source = ir.call(ir.perform("Random"), [ir.integer(1)])
  let initial = empty_context()
  let assert #(run.Concluded(value), updated, []) = execute(source, initial)
  assert v.Integer(0) == value
  assert initial == updated
}

pub fn asynchronous_effect_test() {
  let source = ir.call(ir.perform("Alert"), [ir.string("hi")])
  let initial = empty_context()
  let assert #(run.Handling(0, env:, k:), updated, [task]) =
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
  let initial = empty_context()
  let assert #(run.Handling(0, env:, k:), updated, [effect]) =
    execute(source, initial)
  assert 1 == updated.counter

  let assert browser.Spotless(harness.DNSimple, _, resume:) = effect
  let response =
    token.Response(
      access_token: "dns_tok",
      token_type: "",
      expires_in: None,
      scope: [],
      refresh_token: None,
    )
  let assert SpotlessConnectCompleted(service, result) = resume(Ok(response))
  let #(updated, effects) = run.connect_completed(updated, service, result)
  let assert [] = updated.connecting
  let assert [browser.Fetch(request:, resume:)] = effects
  assert "/proxy/dnsimple/v2/accounts" == request.path
  assert "eyg.test" == request.host
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
  let assert #(run.Handling(1, env:, k:), updated, [effect]) =
    execute(source, updated)
  assert 2 == updated.counter

  let assert browser.Fetch(request:, resume:) = effect
  assert "/proxy/dnsimple/v2/accounts" == request.path
  assert "eyg.test" == request.host
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
  let initial = empty_context()
  let assert #(run.Pending(dep, env:, k:), updated, []) =
    execute(source, initial)
  assert cache.Content(cid) == dep
  assert 0 == updated.counter
  let assert #(updated, [effect]) = run.flush(updated)
  let assert browser.Fetch(request:, resume:) = effect
  assert "/modules/" <> v1.to_string(cid) == request.path
  let assert ModuleLookupCompleted(cid, result) =
    resume(Ok(module_response(lib)))

  let #(updated, done) = run.get_module_completed(updated, cid, result)
  let assert [#(c, Ok(mod))] = done
  assert dict.new() == updated.cache.fetching_modules
  let #(updated, effects) = run.flush(updated)
  assert [] == effects
  assert cid == c
  let assert #(run.Concluded(value), _updated, []) =
    continue(mod, env, k, updated)
  assert v.Integer(43) == value
}

pub fn invalid_reference_test() {
  let lib = ir.vacant()
  let cid = cid_from_tree(lib)

  let source = ir.get(ir.reference(cid), "count")
  let initial = empty_context()
  let assert #(run.Pending(dep:, env: _, k: _), updated, []) =
    execute(source, initial)
  assert cache.Content(cid) == dep
  assert 0 == updated.counter
  let assert #(updated, [effect]) = run.flush(updated)
  let assert browser.Fetch(request:, resume:) = effect
  assert "/modules/" <> v1.to_string(cid) == request.path
  let assert ModuleLookupCompleted(cid, result) =
    resume(Ok(module_response(lib)))

  let #(updated, done) = run.get_module_completed(updated, cid, result)
  let assert [#(c, Error(reason))] = done

  let #(updated, effects) = run.flush(updated)
  assert [] == effects
  assert cid == c
  assert break.Vacant == reason

  // rerun will fail straight away
  let assert #(run.Exception(break.Vacant), updated2, []) =
    execute(source, updated)
  assert updated == updated2
}

// run builds atop cache
// Tests to show all the statuses

pub fn release_lazy_loads_test() {
  let #(release, source) = simple_package(int.random(100))
  let context = empty_context()
  assert cache.Pulled == context.cache.cursor_status
  let #(run, context, effects) = execute(release_to_source(release), context)
  let assert run.Pending(dep:, env: _, k: _) = run
  assert cache.Release(release) == dep

  // running a function with an unknown package always tries to re pull
  assert cache.ReadyToPull == context.cache.cursor_status

  // There should be no program effects
  assert [] == effects

  let #(context, effects) = run.flush(context)
  assert cache.Pulling == context.cache.cursor_status
  let assert [browser.Fetch(request, resume)] = effects
  assert "/packages/pull" == request.path

  let entries = [archived_package(release)]
  let assert PullPackagesCompleted(result) = resume(Ok(pull_response(entries)))
  assert Ok(entries) == result

  let #(context, done) = run.pull_releases_completed(context, result)
  assert [] == done
  assert cache.Pulled == context.cache.cursor_status

  let #(context, effects) = run.flush(context)
  assert cache.Pulled == context.cache.cursor_status
  let assert [browser.Fetch(request, resume)] = effects
  assert "/modules/" <> v1.to_string(release.module) == request.path
  assert ModuleLookupCompleted(release.module, Ok(source))
    == resume(Ok(module_response(source)))
}

pub fn already_loaded_module_completes_on_release_test() {
  let number = int.random(100)
  let #(release, source) = simple_package(number)
  let context =
    empty_context()
    |> with_module(source)
  let #(run, context, effects) = execute(release_to_source(release), context)
  assert [] == effects

  let entries = [archived_package(release)]
  let #(context, done) = run.pull_releases_completed(context, Ok(entries))
  assert [] == done

  let done = run.new_releases(Ok(entries))
  let #(run, _context, effects) =
    run.apply_new_releases(run, context, expression.resume, done)
  assert [] == effects
  assert run.Concluded(v.Integer(number)) == run
}

// TODO test that if returned module is wrong then state updates
// fn with_module
// dn with_release("a",1,source)

fn with_module(
  context: run.Context(a),
  source: #(ir.Expression(meta), meta),
) -> run.Context(a) {
  let source = ir.map_annotation(source, fn(_) { [] })
  let run.Context(cache:, ..) = context
  let #(cache, done) = cache.with_module(cache, cid_from_tree(source), source)
  let assert [_] = done
  run.Context(..context, cache:)
}

fn simple_package(number) {
  let source = ir.integer(number)
  let cid = cid_from_tree(source)
  let package = "my_package"
  let release = release.Release(package:, version: 1, module: cid)
  #(release, source)
}

fn release_to_source(release) {
  let release.Release(package:, version:, module:) = release
  ir.release(package, version, module)
}

// fn inactive_context() {
//   // let #(context, effects) = run.flush(context() |> run.pull())
//   // // original fetch to pull
//   // let assert [_] = effects
//   // echo context.cache.cursor_status
//   empty_context()
// }

fn archived_package(release: release.Release) {
  let assert 1 = release.version
  let entry =
    publisher.first(random_cid(), "abc", release.package, release.module)
  // let entries = [
  ledger_schema.ArchivedEntry(
    cursor: 1,
    cid: random_cid(),
    payload: json.to_string(publisher.encode(entry)),
    entity: random_cid(),
    sequence: 100,
    previous: None,
    type_: "todo",
  )
  // ]
  // let assert PullPackagesCompleted(result) = resume(Ok(pull_response(entries)))
  // assert Ok(entries) == result
}

// fn payload_encode(payload) {
//   case payload {
//     release.Release(package:, version:, module:) -> {
//       #(
//         "release",
//         codec.object([
//           #("package", codec.string(package)),
//           #("version", codec.int(version)),
//           #("module", codec.cid(module)),
//         ]),
//       )
//     }
//   }
// }

pub fn cid_from_tree(source) {
  let cid.Sha256(bytes:, resume:) = cid.from_tree(source)
  resume(crypto.hash(crypto.Sha256, bytes))
}

fn random_cid() {
  let multihash =
    hashes.Multihash(hashes.Sha256, crypto.strong_random_bytes(10))
  v1.Cid(codec.code(), multihash)
}

pub fn cid_from_block(block) {
  let cid.Sha256(bytes:, resume:) = cid.from_block(block)
  resume(crypto.hash(crypto.Sha256, bytes))
}

pub fn pull_response(entries) {
  schema.entries_response_encode(entries)
  |> json.to_string
  |> bit_array.from_string
  |> response.set_body(response.new(200), _)
}

pub fn module_response(source) {
  let body = dag_json.to_block(source)
  response.new(200)
  |> response.set_body(body)
}
