import eyg/hub/cache
import eyg/hub/publisher
import eyg/interpreter/value as v
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/crypto
import gleam/dict
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/uri
import midas/continuation
import multiformats/cid/v1
import ogre/origin
import untethered/ledger/schema
import untethered/substrate

// A hub holding some modules and a release log, answering straight away.
type Hub {
  Hub(
    modules: List(#(v1.Cid, ir.Node(Nil))),
    entries: List(schema.ArchivedEntry),
  )
}

fn load(hub: Hub, source) {
  load_into(cache.ready(), hub, source)
}

fn load_into(cache, hub: Hub, source) {
  cache.load(
    cache,
    source,
    origin.https("hub.test"),
    fn(request) { continuation.return(Ok(answer(hub, request))) },
    fn(_, bytes) { continuation.return(crypto.hash(crypto.Sha256, bytes)) },
    fn(_) { Nil },
  )(fn(cache) { cache })
}

fn answer(hub: Hub, request: Request(BitArray)) {
  case request.path {
    "/modules/" <> id -> {
      let found =
        list.find(hub.modules, fn(module) { v1.to_string(module.0) == id })
      case found {
        Ok(#(_, source)) ->
          response.new(200) |> response.set_body(dag_json.to_block(source))
        Error(Nil) -> response.new(404) |> response.set_body(<<>>)
      }
    }
    "/packages/pull" -> {
      let since =
        request.query
        |> option.to_result(Nil)
        |> result.try(uri.parse_query)
        |> result.try(list.key_find(_, "since"))
        |> result.try(int.parse)
        |> result.unwrap(0)
      let entries = list.filter(hub.entries, fn(entry) { entry.cursor > since })
      let body = json.to_string(schema.entries_response_encode(entries))
      response.new(200) |> response.set_body(<<body:utf8>>)
    }
    _ -> response.new(404) |> response.set_body(<<>>)
  }
}

fn module(source) {
  let source = ir.clear_annotation(source)
  #(
    cid.from_tree(source, fn(bytes) {
      continuation.return(crypto.hash(crypto.Sha256, bytes))
    })(fn(x) { x }),
    source,
  )
}

fn release(package, version, cursor, module: #(v1.Cid, ir.Node(Nil))) {
  let signatory = module.0
  let entry =
    substrate.Entry(
      sequence: version,
      previous: None,
      signatory:,
      key: "test-key",
      content: publisher.Release(package:, version:, module: module.0),
    )
  schema.ArchivedEntry(
    cursor:,
    cid: module.0,
    payload: json.to_string(publisher.encode(entry)),
    entity: signatory,
    sequence: version,
    previous: None,
    type_: "release",
  )
}

fn value(cache, reference) {
  cache.get_reference(cache, reference)
  |> result.map(fn(module: cache.Module(Nil)) { module.value })
}

pub fn loading_a_package_fetches_its_latest_release_test() {
  let one = module(ir.integer(1))
  let two = module(ir.integer(2))
  let hub =
    Hub(modules: [one, two], entries: [
      release("std", 1, 1, one),
      release("std", 2, 2, two),
    ])
  let cache = load(hub, ir.package("std"))
  assert value(cache, ir.Package("std")) == Ok(v.Integer(2))
  assert cache.cursor_status == cache.Pulled
}

pub fn loading_follows_a_release_to_its_dependencies_test() {
  let base = module(ir.integer(40))
  let top = module(ir.add(ir.reference(base.0), ir.integer(2)))
  let hub = Hub(modules: [base, top], entries: [release("top", 1, 1, top)])
  let cache = load(hub, ir.version("top", 1))
  assert value(cache, ir.Version("top", 1)) == Ok(v.Integer(42))
  assert dict.size(cache.modules) == 2
}

pub fn a_module_the_hub_does_not_have_ends_the_load_test() {
  let missing = module(ir.integer(9))
  let hub = Hub(modules: [], entries: [release("gone", 1, 1, missing)])
  let cache = load(hub, ir.package("gone"))
  assert value(cache, ir.Package("gone")) == Error(Nil)
  let assert Error(cache.Failed(_)) = cache.get_module(cache, missing.0)
}

pub fn a_source_without_references_needs_nothing_test() {
  let cache = load_into(cache.empty(), Hub([], []), ir.integer(1))
  assert cache == cache.empty()
}

pub fn loading_an_existing_graph_performs_no_host_operations_test() {
  let base = module(ir.integer(40))
  let top = module(ir.add(ir.reference(base.0), ir.integer(2)))
  let source = ir.package("top")
  let loaded = load(Hub([base, top], [release("top", 1, 1, top)]), source)
  let reused =
    cache.load(
      loaded,
      source,
      origin.https("offline.invalid"),
      fn(_) { panic as "cached graph fetched from the network" },
      fn(_, _) { panic as "cached graph hashed again" },
      fn(_) { Nil },
    )(fn(cache) { cache })
  assert reused == loaded
  assert value(reused, ir.Package("top")) == Ok(v.Integer(42))
}

pub fn a_corrupt_module_does_not_enter_the_loaded_cache_test() {
  let one = module(ir.integer(1))
  let loaded = load(Hub([#(one.0, ir.integer(2))], []), ir.reference(one.0))
  assert value(loaded, ir.Content(one.0)) == Error(Nil)
  let assert Error(cache.Failed(_)) = cache.get_module(loaded, one.0)
}
