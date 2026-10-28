//// A hub serving modules and releases to sandboxed programs.

import eyg/hub/publisher
import eyg/hub/schema
import eyg/ir/dag_json
import eyg/ir/tree as ir
import glasshouse/store
import gleam/crypto
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import multiformats/cid/v1
import untethered/substrate

pub fn sha256(bytes) {
  crypto.hash(crypto.Sha256, bytes)
}

pub fn cid(module: ir.Node(Nil)) -> v1.Cid {
  store.cid(dag_json.to_block(module), sha256)
}

pub type Hub {
  Hub(modules: List(ir.Node(Nil)), releases: List(#(String, Int, v1.Cid)))
}

/// Handle requests as a hub, recording every request made.
pub fn handle(request: request.Request(BitArray), hub: Hub, requests) {
  let response = case request.path {
    "/packages/pull" -> {
      let since =
        request.get_query(request)
        |> result.unwrap([])
        |> list.key_find("since")
        |> result.try(int.parse)
        |> result.unwrap(0)
      let entries =
        list.index_map(hub.releases, fn(release, i) {
          let #(package, version, module) = release
          let entry =
            substrate.Entry(
              sequence: version,
              previous: None,
              signatory: module,
              key: "key",
              content: publisher.Release(package:, version:, module:),
            )
          schema.package_entry(
            cursor: i + 1,
            cid: module,
            payload: json.to_string(publisher.encode(entry)),
            entity: module,
            sequence: version,
            previous: None,
            type_: "release",
          )
        })
        |> list.filter(fn(entry) { entry.cursor > since })
      response.new(200)
      |> response.set_body(<<
        json.to_string(schema.entries_response_encode(entries)):utf8,
      >>)
    }
    "/modules/" <> id ->
      case list.find(hub.modules, fn(m) { v1.to_string(cid(m)) == id }) {
        Ok(module) ->
          response.new(200) |> response.set_body(dag_json.to_block(module))
        Error(Nil) -> response.new(404) |> response.set_body(<<>>)
      }
    _ -> response.new(404) |> response.set_body(<<>>)
  }
  #(Ok(response), [request.path, ..requests])
}
