import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import glasshouse/bundle
import glasshouse/sha256
import glasshouse/store
import gleam/http/response
import gleam/list
import gleam/option.{Some}
import gleam/string
import loam/environment
import loam/execute
import loam/hub_mock
import loam/package
import loam/sandbox
import loam/source
import loam/virtual
import multiformats/cid/v1
import ogre/origin

pub fn transitive_pinned_graph_is_portable_and_deduplicated_test() {
  let leaf = #(ir.Integer(42), Nil)
  let leaf_id = hub_mock.cid(leaf)
  let parent = #(ir.Reference(ir.Pinned(ir.Release("base", 3, leaf_id))), Nil)
  let parent_id = hub_mock.cid(parent)
  let root = #(
    ir.Let("first", #(ir.Reference(ir.Content(parent_id)), Nil), #(
      ir.Reference(ir.Content(leaf_id)),
      Nil,
    )),
    Nil,
  )
  let root_id = hub_mock.cid(root)
  let hub = hub_mock.Hub([leaf, parent, root], [])
  let host =
    sandbox.sandbox()
    |> sandbox.with_network(
      fn(request, calls) { hub_mock.handle(request, hub, calls) },
      [],
    )
  let assert #(sandbox.Returned(Ok(acquired)), host) =
    package.acquire(
      "@demo:1:" <> v1.to_string(root_id),
      origin.https("eyg.run"),
    )
    |> sandbox.run(host)
  assert list.length(host.network_state) == 3
  assert acquired.root == v1.to_string(root_id)
  assert list.length(store.to_list(acquired.store)) == 3
  assert bundle.from_string(bundle.to_string(acquired), sha256.hash)
    == Ok(acquired)
  let assert #(sandbox.Returned(Ok(prepared)), _) =
    package.prepare(acquired, origin.https("offline.example"))
    |> sandbox.run(sandbox.sandbox())
  let assert Ok(environment) = environment.open(prepared)
  let assert Ok(node) = source.parse("import \"entry.eyg\"", source.Inline)
  let state = environment.execution_state(environment, environment.hub)
  let assert #(sandbox.Returned(#(Ok(#(Ok(#(Some(value), _)), _)), _)), _) =
    virtual.run(execute.block(node, [], state), virtual.fork(environment))
    |> sandbox.run(sandbox.sandbox())
  assert value == v.Integer(42)
}

pub fn wrong_content_cannot_enter_the_bundle_test() {
  let expected = hub_mock.cid(#(ir.Integer(42), Nil))
  let host =
    sandbox.sandbox()
    |> sandbox.with_network(
      fn(_, _) {
        #(
          Ok(
            response.new(200)
            |> response.set_body(dag_json.to_block(#(ir.Integer(43), Nil))),
          ),
          Nil,
        )
      },
      Nil,
    )
  let assert #(sandbox.Returned(Error(reason)), _) =
    package.acquire("#" <> v1.to_string(expected), origin.https("eyg.run"))
    |> sandbox.run(host)
  assert string.contains(reason, "wrong cid")
}

pub fn mutable_roots_and_nested_dependencies_are_refused_test() {
  let host = sandbox.sandbox()
  list.each(["@demo", "@demo:1", "import \"file.eyg\"", "42"], fn(reference) {
    let assert #(sandbox.Returned(Error(_)), _) =
      package.acquire(reference, origin.https("eyg.run")) |> sandbox.run(host)
  })
  let module = #(ir.Reference(ir.Package("floating")), Nil)
  let hub = hub_mock.Hub([module], [])
  let host =
    host
    |> sandbox.with_network(
      fn(request, calls) { hub_mock.handle(request, hub, calls) },
      [],
    )
  let assert #(sandbox.Returned(Error(_)), _) =
    package.acquire(
      "#" <> v1.to_string(hub_mock.cid(module)),
      origin.https("eyg.run"),
    )
    |> sandbox.run(host)
}
