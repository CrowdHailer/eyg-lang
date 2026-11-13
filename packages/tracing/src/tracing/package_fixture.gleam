//// A real HTTP hub fixture for package walkthroughs, built from repository IR.

import eyg/hub/publisher
import eyg/ir/cid
import eyg/ir/dag_json
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/uri
import javascript/mutable_reference as cell
import midas/continuation
import multiformats/cid/v1
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server
import simplifile
import untethered/ledger/schema
import untethered/substrate

pub type Fixture {
  Fixture(server: server.Server, count: fn() -> Int, reference: String)
}

pub fn main() {
  let assert Ok(fixture) = start()
  io.println("Repository package fixture listening on http://127.0.0.1:7207")
  io.println("Standard reference: " <> fixture.reference)
}

pub fn start() {
  start_with_modules([])
}

/// Add pure application modules to the same real hub protocol fixture.
pub fn start_with_modules(extra) {
  let assert Ok(text) =
    simplifile.read("../../eyg_packages/standard/index.eyg.json")
  let assert Ok(tree) = json.parse(text, dag_json.decoder(Nil))
  let id =
    cid.from_tree(tree, fn(bytes) {
      continuation.return(crypto.hash(crypto.Sha256, bytes))
    })(fn(value) { value })
  let assert Ok(body) = dag_json.to_block(tree) |> bit_array.to_string
  let payload =
    publisher.encode(substrate.Entry(
      1,
      None,
      id,
      "fixture",
      publisher.Release("standard", 1, id),
    ))
    |> json.to_string
  let entries = [schema.ArchivedEntry(1, id, payload, id, 1, None, "release")]
  let additional =
    list.map(extra, fn(tree) {
      let cid =
        cid.from_tree(tree, fn(bytes) {
          continuation.return(crypto.hash(crypto.Sha256, bytes))
        })(fn(value) { value })
      let assert Ok(body) = dag_json.to_block(tree) |> bit_array.to_string
      #(v1.to_string(cid), body)
    })
  let modules = dict.from_list([#(v1.to_string(id), body), ..additional])
  let count = cell.new(0)
  let assert Ok(bun) = runtime.get()
  let assert Ok(response) = fetch.get_response()
  let serving =
    server.serve(
      bun,
      server.Options(7207, "127.0.0.1", fn(request) {
        let assert Ok(url) = uri.parse(fetch.request_url(request))
        let #(status, body) = case url.path {
          "/stats" -> #(
            200,
            json.object([#("requests", json.int(cell.get(count)))])
              |> json.to_string,
          )
          "/packages/pull" -> {
            let _ = cell.update(count, fn(value) { value + 1 })
            let since = case url.query {
              Some(query) ->
                uri.parse_query(query)
                |> result.try(list.key_find(_, "since"))
                |> result.try(int.parse)
                |> result.unwrap(0)
              None -> 0
            }
            #(
              200,
              list.filter(entries, fn(entry) { entry.cursor > since })
                |> schema.entries_response_encode
                |> json.to_string,
            )
          }
          "/modules/" <> id -> {
            let _ = cell.update(count, fn(value) { value + 1 })
            case dict.get(modules, id) {
              Ok(body) -> #(200, body)
              Error(_) -> #(204, "")
            }
          }
          _ -> #(404, "")
        }
        let assert Ok(reply) =
          fetch.new_response(response, body, status, [
            #("content-type", "application/json"),
          ])
        promise.resolve(reply)
      }),
    )
  result.map(serving, fn(server) {
    Fixture(
      server,
      fn() { cell.get(count) },
      "@standard:1:" <> v1.to_string(id),
    )
  })
}
