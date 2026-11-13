import eyg/interpreter/value as v
import eyg/ir/tree as ir
import glasshouse/bundle
import glasshouse/sha256
import glasshouse/store
import gleam/http/request
import gleam/http/response
import gleam/option.{None, Some}
import loam/acquire
import loam/environment
import loam/execute
import loam/hub_mock
import loam/prepare
import loam/sandbox
import loam/sandbox/fs
import loam/source
import loam/virtual
import multiformats/cid/v1
import ogre/origin

pub fn http_fetches_are_verified_against_locked_content_test() {
  let assert Ok(request) = request.to("https://example.com/input")
  let request = request.set_body(request, <<>>)
  let host =
    sandbox.sandbox()
    |> sandbox.with_network(
      fn(_, _) {
        #(Ok(response.new(200) |> response.set_body(<<"input">>)), Nil)
      },
      Nil,
    )
  let assert #(sandbox.Returned(Ok(input)), _) =
    acquire.http(request, None, sha256.hash) |> sandbox.run(host)
  assert store.get_binary(input.store, input.root) == Ok(<<"input">>)
  let assert #(sandbox.Returned(Ok(same)), _) =
    acquire.http(request, Some(input.root), sha256.hash) |> sandbox.run(host)
  assert same == input
  let assert #(sandbox.Returned(Error(_)), _) =
    acquire.http(request, Some("wrong"), sha256.hash) |> sandbox.run(host)
}

pub fn content_reference_closure_survives_transfer_without_the_hub_test() {
  let module = #(ir.Integer(42), Nil)
  let cid = hub_mock.cid(module)
  let hub = hub_mock.Hub([module], [])
  let host =
    sandbox.sandbox()
    |> sandbox.with_file("/project/main.eyg", "#" <> v1.to_string(cid))
    |> sandbox.with_directory("/project/empty")
    |> sandbox.with_network(
      fn(request, calls) { hub_mock.handle(request, hub, calls) },
      [],
    )
  let assert #(sandbox.Returned(Ok(tree)), host) =
    acquire.local("/project", [], sha256.hash) |> sandbox.run(host)
  let assert #(sandbox.Returned(Ok(input)), host) =
    prepare.prepare(tree, "main.eyg", origin.https("eyg.run"), sha256.hash)
    |> sandbox.run(host)
  assert host.network_state != []
  let assert Ok(input) =
    bundle.from_string(bundle.to_string(input), sha256.hash)
  assert store.get_node(input.store, v1.to_string(cid)) == Ok(module)
  let assert Ok(environment) = environment.open(input)
  assert fs.read_directory(environment.files, "/workspace/empty") == Ok([])
}

pub fn named_packages_use_the_prepared_lock_without_refreshing_the_hub_test() {
  let module = #(ir.Integer(42), Nil)
  let cid = hub_mock.cid(module)
  let hub = hub_mock.Hub([module], [#("demo", 1, cid)])
  let host =
    sandbox.sandbox()
    |> sandbox.with_file("/project/main.eyg", "@demo")
    |> sandbox.with_network(
      fn(request, calls) { hub_mock.handle(request, hub, calls) },
      [],
    )
  let assert #(sandbox.Returned(Ok(tree)), host) =
    acquire.local("/project", [], sha256.hash) |> sandbox.run(host)
  let assert #(sandbox.Returned(Ok(input)), _) =
    prepare.prepare(tree, "main.eyg", origin.https("eyg.run"), sha256.hash)
    |> sandbox.run(host)
  let assert Ok(environment) = environment.open(input)
  let assert Ok(node) = source.parse("@demo", source.Inline)
  let state = environment.execution_state(environment, environment.hub)
  let effect = execute.block(node, [], state)
  let assert #(sandbox.Returned(#(Ok(#(Ok(_), _)), _)), _) =
    virtual.run(effect, virtual.fork(environment))
    |> sandbox.run(sandbox.sandbox())
}

pub fn nested_immutable_releases_remain_available_offline_test() {
  let leaf = #(ir.Integer(42), Nil)
  let root = #(
    ir.Reference(ir.Pinned(ir.Release("base", 3, hub_mock.cid(leaf)))),
    Nil,
  )
  let hub = hub_mock.Hub([root, leaf], [])
  let host =
    sandbox.sandbox()
    |> sandbox.with_file(
      "/project/main.eyg",
      "#" <> v1.to_string(hub_mock.cid(root)),
    )
    |> sandbox.with_network(
      fn(request, calls) { hub_mock.handle(request, hub, calls) },
      [],
    )
  let assert #(sandbox.Returned(Ok(tree)), host) =
    acquire.local("/project", [], sha256.hash) |> sandbox.run(host)
  let assert #(sandbox.Returned(Ok(input)), _) =
    prepare.prepare(tree, "main.eyg", origin.https("eyg.run"), sha256.hash)
    |> sandbox.run(host)
  let assert Ok(environment) = environment.open(input)
  let assert Ok(node) = source.parse("import \"main.eyg\"", source.Inline)
  let state = environment.execution_state(environment, environment.hub)
  let assert #(sandbox.Returned(#(Ok(#(Ok(#(Some(value), _)), _)), _)), _) =
    virtual.run(execute.block(node, [], state), virtual.fork(environment))
    |> sandbox.run(sandbox.sandbox())
  assert value == v.Integer(42)
}
