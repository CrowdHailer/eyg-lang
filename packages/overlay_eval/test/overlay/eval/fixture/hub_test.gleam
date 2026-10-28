import eyg/hub/client
import eyg/hub/publisher
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import multiformats/cid/v1
import ogre/operation
import ogre/origin
import overlay/eval/fixture/hub
import overlay/eval/module
import untethered/ledger/schema

fn fixture() {
  let assert Ok(hub) =
    hub.publish_directory(hub.new(), "test/fixtures/packages")
  hub
}

fn pull(hub, since) {
  let request =
    client.pull_packages_request(
      schema.PullParameters(since:, limit: 1000, entities: []),
      origin.https("eyg.test"),
    )
  let assert Ok(response) = hub.handle(hub, request)
  let assert Ok(schema.PullResponse(entries:)) =
    client.pull_packages_response(response)
  entries
}

pub fn directories_with_an_index_are_published_test() {
  let hub = fixture()
  // amplify uses greeting, so it is published after it.
  assert ["greeting", "numbers", "amplify"]
    == list.map(hub.releases, fn(release) { release.package })

  let entries = pull(hub, 0)
  assert [1, 2, 3] == list.map(entries, fn(entry) { entry.cursor })
  let releases =
    list.map(entries, fn(entry) {
      let assert Ok(payload) = json.parse(entry.payload, publisher.decoder())
      payload.content
    })
  let assert [
    publisher.Release("greeting", 1, _),
    publisher.Release("numbers", 1, _),
    publisher.Release("amplify", 1, _),
  ] = releases
  assert [] == pull(hub, 3)
}

pub fn modules_are_fetched_by_content_id_test() {
  let hub = fixture()
  let assert Ok(loaded) =
    module.load("test/fixtures/packages/greeting/index.eyg")
  let request =
    client.fetch_module_request(loaded.cid, origin.https("eyg.test"))
  let assert Ok(response) = hub.handle(hub, request)
  let assert Ok(Some(source)) = client.fetch_module_response(response)
  assert loaded.cid == module.cid(source)

  // The hub answers an unknown module with no content.
  let request =
    client.fetch_module_request(dag_json.vacant_cid, origin.https("eyg.test"))
  let assert Ok(response) = hub.handle(hub, request)
  assert 204 == response.status
}

pub fn later_releases_are_new_versions_test() {
  let assert Ok(loaded) =
    module.load("test/fixtures/packages/numbers/index.eyg.json")
  let hub =
    hub.new()
    |> hub.publish("numbers", loaded)
    |> hub.publish("numbers", loaded)
  assert [1, 2] == list.map(hub.releases, fn(release) { release.version })
}

pub fn other_requests_are_not_for_the_hub_test() {
  let request =
    operation.get("/guides/syntax.md")
    |> operation.to_request(origin.https("eyg.test"))
  assert Error(Nil) == hub.handle(hub.new(), request)
}

pub fn packages_are_published_after_the_packages_they_use_test() {
  let hub = fixture()
  let assert Ok(greeting) =
    list.find(hub.releases, fn(release) { release.package == "greeting" })
  let assert Ok(amplify) =
    list.find(hub.releases, fn(release) { release.package == "amplify" })
  let assert Ok(block) = dict.get(hub.blocks, v1.to_string(amplify.module))
  let assert Ok(source) = json.parse_bits(block, dag_json.decoder(Nil))
  assert [ir.Pinned(ir.Release("greeting", 1, greeting.module))]
    == ir.list_references(source)
}

pub fn references_resolve_to_releases_test() {
  let hub = fixture()
  let resolve = hub.resolve(hub)
  let assert Ok(ir.Release("numbers", 1, _)) = resolve("numbers", None)
  let assert Ok(ir.Release("numbers", 1, _)) = resolve("numbers", Some(1))
  assert Error(Nil) == resolve("numbers", Some(2))
  assert Error(Nil) == resolve("missing", None)
}
