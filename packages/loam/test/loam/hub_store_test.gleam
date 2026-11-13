import eyg/hub/cache
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict
import gleam/http/response
import gleam/option.{Some}
import gleeunit/should
import loam/execute
import loam/hub_mock
import loam/hub_store
import loam/sandbox
import loam/sandbox/fs
import loam/source
import midas/effect
import multiformats/cid/v1
import ogre/origin

const store = "/cache"

fn module() {
  #(ir.Integer(42), Nil)
}

fn module_path() {
  store <> "/modules/" <> v1.to_string(hub_mock.cid(module()))
}

fn host() {
  origin.https("hub.test")
}

fn online() {
  sandbox.sandbox()
  |> sandbox.with_network(
    fn(request, requests) {
      hub_mock.handle(
        request,
        hub_mock.Hub([module()], [#("answer", 1, hub_mock.cid(module()))]),
        requests,
      )
    },
    [],
  )
}

pub fn validated_modules_persist_and_resolve_in_a_new_offline_runtime_test() {
  let reference = ir.Package("answer")
  let state = execute.State(host(), cache.empty(), Some(store))
  let assert #(sandbox.Returned(#(Ok(value), _)), stored) =
    execute.lookup(reference, source.Inline, state) |> sandbox.run(online())
  assert value == v.Integer(42)
  assert fs.read_bits(stored.file_system, module_path())
    == Ok(dag_json.to_block(module()))
  let offline =
    sandbox.with_network(
      stored,
      fn(_, _) { #(Error(effect.NetworkError("offline")), Nil) },
      Nil,
    )
  let assert #(sandbox.Returned(#(Ok(reused), _)), _) =
    execute.lookup(reference, source.Inline, state) |> sandbox.run(offline)
  assert reused == value
}

pub fn valid_immutable_modules_make_no_network_request_test() {
  let environment =
    sandbox.sandbox()
    |> sandbox.with_file_bits(module_path(), dag_json.to_block(module()))
  let assert #(sandbox.Returned(cache.FetchModuleCompleted(_, Ok(found))), _) =
    hub_store.compute(cache.FetchModule(hub_mock.cid(module())), host(), store)
    |> sandbox.run(environment)
  assert found == module()
}

pub fn corrupt_stored_modules_are_refetched_and_replaced_test() {
  let environment =
    online()
    |> sandbox.with_file_bits(
      module_path(),
      dag_json.to_block(#(ir.Integer(0), Nil)),
    )
  let assert #(
    sandbox.Returned(cache.FetchModuleCompleted(_, Ok(found))),
    stored,
  ) =
    hub_store.compute(cache.FetchModule(hub_mock.cid(module())), host(), store)
    |> sandbox.run(environment)
  assert found == module()
  assert stored.network_state
    == ["/modules/" <> v1.to_string(hub_mock.cid(module()))]
  assert fs.read_bits(stored.file_system, module_path())
    == Ok(dag_json.to_block(module()))
}

pub fn wrong_hash_and_bad_ledger_responses_do_not_poison_the_store_test() {
  let wrong =
    response.new(200)
    |> response.set_body(dag_json.to_block(#(ir.Integer(0), Nil)))
  let environment = sandbox.save_and_return(sandbox.sandbox(), wrong)
  let assert #(
    sandbox.Returned(cache.FetchModuleCompleted(_, Error(_))),
    stored,
  ) =
    hub_store.compute(cache.FetchModule(hub_mock.cid(module())), host(), store)
    |> sandbox.run(environment)
  fs.read(stored.file_system, module_path()) |> should.be_error
  let bad = response.new(200) |> response.set_body(<<"invalid JSON":utf8>>)
  let environment = sandbox.save_and_return(sandbox.sandbox(), bad)
  let assert #(sandbox.Returned(cache.PullPackagesCompleted(Error(_))), stored) =
    hub_store.compute(cache.PullPackages(0), host(), store)
    |> sandbox.run(environment)
  fs.read(stored.file_system, store <> "/packages/0") |> should.be_error
}

pub fn ledger_pages_still_refresh_online_test() {
  let assert #(sandbox.Returned(cache.PullPackagesCompleted(Ok(_))), stored) =
    hub_store.compute(cache.PullPackages(0), host(), store)
    |> sandbox.run(online())
  let refreshed =
    sandbox.with_network(
      stored,
      fn(request, requests) {
        hub_mock.handle(
          request,
          hub_mock.Hub([module()], [#("answer", 2, hub_mock.cid(module()))]),
          requests,
        )
      },
      [],
    )
  let assert #(
    sandbox.Returned(cache.PullPackagesCompleted(Ok(entries))),
    refreshed,
  ) =
    hub_store.compute(cache.PullPackages(0), host(), store)
    |> sandbox.run(refreshed)
  assert refreshed.network_state == ["/packages/pull"]
  let #(cache, _) = cache.pull_packages_completed(cache.empty(), Ok(entries))
  let assert Ok(entry) = dict.get(cache.packages, "answer")
  assert entry.version == 2
}

pub fn failed_cache_writes_preserve_the_verified_network_result_test() {
  let environment = online() |> sandbox.with_file_bits(store, <<>>)
  let assert #(sandbox.Returned(cache.FetchModuleCompleted(_, Ok(found))), _) =
    hub_store.compute(cache.FetchModule(hub_mock.cid(module())), host(), store)
    |> sandbox.run(environment)
  assert found == module()
}
