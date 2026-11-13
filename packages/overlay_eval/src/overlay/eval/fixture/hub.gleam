//// A hub serving local modules and packages.
////
//// Sessions pull the package log and fetch modules over HTTP exactly as they
//// do from eyg.run, the fixture answers from memory. Releases are recorded
//// without signatures, the cache does not check them.

import eyg/hub/publisher
import eyg/ir/dag_json
import eyg/ir/tree as ir
import filepath
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import overlay/eval/module
import simplifile
import untethered/ledger/schema
import untethered/substrate

pub type Hub {
  Hub(blocks: Dict(String, BitArray), releases: List(Release))
}

pub type Release {
  Release(package: String, version: Int, module: v1.Cid)
}

pub fn new() -> Hub {
  Hub(blocks: dict.new(), releases: [])
}

/// Store a module and every module it imports, so they can be fetched by
/// content id.
pub fn add(hub: Hub, loaded: module.Loaded) -> Hub {
  Hub(..hub, blocks: dict.merge(hub.blocks, loaded.blocks))
}

/// Store a module and release it as the next version of a package.
pub fn publish(hub: Hub, package: String, loaded: module.Loaded) -> Hub {
  let version =
    list.count(hub.releases, fn(release) { release.package == package }) + 1
  let release = Release(package:, version:, module: loaded.cid)
  Hub(..add(hub, loaded), releases: list.append(hub.releases, [release]))
}

/// Pin package references to the hub's releases: a name to its latest
/// release and a version to that release.
pub fn resolve(hub: Hub) -> module.Resolve {
  fn(package, version) {
    let releases =
      list.filter(hub.releases, fn(release) { release.package == package })
    let release = case version {
      None -> list.last(releases)
      Some(version) ->
        list.find(releases, fn(release) { release.version == version })
    }
    result.map(release, fn(release) {
      ir.Release(package:, version: release.version, module: release.module)
    })
  }
}

/// Publish every package in a directory, a package is a directory with an
/// `index.eyg` or `index.eyg.json` module named after the directory.
///
/// Packages are published after the packages they reference, and references
/// are pinned to those releases, as `eyg share` pins them.
pub fn publish_directory(hub: Hub, root: String) -> Result(Hub, String) {
  use names <- result.try(
    simplifile.read_directory(root)
    |> result.map_error(fn(reason) {
      "unable to list " <> root <> ": " <> simplifile.describe_error(reason)
    }),
  )
  use packages <- result.try(
    list.sort(names, string.compare)
    |> list.try_fold([], fn(packages, name) {
      let directory = filepath.join(root, name)
      case index(directory) {
        Ok(path) -> {
          use loaded <- result.map(module.load(path))
          [#(name, path, module.packages(loaded)), ..packages]
        }
        Error(Nil) -> Ok(packages)
      }
    })
    |> result.map(list.reverse),
  )
  let names = list.map(packages, fn(package) { package.0 })
  publish_in_order(hub, packages, names)
}

fn index(directory) {
  ["index.eyg", "source/index.eyg", "index.eyg.json"]
  |> list.map(filepath.join(directory, _))
  |> list.find(fn(path) { simplifile.is_file(path) == Ok(True) })
}

fn publish_in_order(hub: Hub, waiting, names) {
  case waiting {
    [] -> Ok(hub)
    _ -> {
      let published = list.map(hub.releases, fn(release) { release.package })
      // A package is ready once every package it uses from this directory is out.
      let ready = fn(package: #(String, String, List(String))) {
        list.all(package.2, fn(used) {
          used == package.0
          || list.contains(published, used)
          || !list.contains(names, used)
        })
      }
      let #(next, rest) = case list.partition(waiting, ready) {
        // Packages that use each other are published in name order.
        #([], [first, ..rest]) -> #([first], rest)
        split -> split
      }
      use hub <- result.try(
        list.try_fold(next, hub, fn(hub, package) {
          let #(name, path, _) = package
          use loaded <- result.map(module.load_pinned(path, resolve(hub)))
          publish(hub, name, loaded)
        }),
      )
      publish_in_order(hub, rest, names)
    }
  }
}

/// Answer a request if it is for the hub API.
pub fn handle(
  hub: Hub,
  request: Request(BitArray),
) -> Result(Response(BitArray), Nil) {
  case request.method, request.path_segments(request) {
    http.Get, ["modules", cid] -> Ok(module_response(hub, cid))
    http.Get, ["packages", "pull"] -> Ok(pull_response(hub, request))
    _, _ -> Error(Nil)
  }
}

fn module_response(hub: Hub, cid) {
  case dict.get(hub.blocks, cid) {
    Ok(block) ->
      response.new(200)
      |> response.set_header("content-type", "application/json")
      |> response.set_body(block)
    // The hub answers an unknown module with no content.
    Error(Nil) -> response.new(204) |> response.set_body(<<>>)
  }
}

fn pull_response(hub: Hub, request) {
  let schema.PullParameters(since:, limit:, entities: _) =
    schema.pull_parameters_from_request(request)
  let entries =
    list.index_map(hub.releases, fn(release, index) {
      archived_entry(release, index + 1)
    })
    |> list.filter(fn(entry) { entry.cursor > since })
    |> list.take(limit)
  let body =
    json.object([
      #("entries", json.array(entries, schema.archived_entry_encode)),
    ])
    |> json.to_string
  response.new(200)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(<<body:utf8>>)
}

fn archived_entry(release: Release, cursor) {
  let Release(package:, version:, module:) = release
  let entry =
    substrate.Entry(
      sequence: version,
      previous: None,
      signatory: dag_json.vacant_cid,
      key: "eval",
      content: publisher.Release(package:, version:, module:),
    )
  let assert Ok(payload) = bit_array.to_string(publisher.to_bytes(entry))
  schema.ArchivedEntry(
    cursor:,
    cid: module,
    payload:,
    entity: dag_json.vacant_cid,
    sequence: version,
    previous: None,
    type_: "release",
  )
}
