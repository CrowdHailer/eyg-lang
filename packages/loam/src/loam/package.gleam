//// Acquire a complete EYG module graph by immutable reference, without evaluation.

import eyg/hub/client
import eyg/ir/tree as ir
import glasshouse/bundle
import glasshouse/sha256
import glasshouse/store
import gleam/dict
import gleam/list
import gleam/result
import loam/environment
import loam/prepare
import loam/sandbox/fs
import loam/source
import loam/system
import multiformats/cid/v1
import ogre/origin

pub fn acquire(
  reference: String,
  hub: origin.Origin,
) -> system.Effect(Result(bundle.Bundle, String)) {
  use node <- system.try(source.parse(reference, source.Inline))
  use cid <- system.try(case node.0 {
    ir.Reference(reference) -> immutable(reference)
    _ -> Error("expected #<cid> or @name:version:<cid>")
  })
  use blocks <- system.then(fetch(cid, hub, store.new()))
  use blocks <- system.try(blocks)
  system.Done(bundle.validate(
    bundle.new(v1.to_string(cid), blocks),
    sha256.hash,
  ))
}

/// Convert a verified package closure to a sealed environment, entirely offline.
pub fn prepare(
  input: bundle.Bundle,
  hub: origin.Origin,
) -> system.Effect(Result(bundle.Bundle, String)) {
  use input <- system.try(bundle.validate(input, sha256.hash))
  let tree = fs.directory([#("entry.eyg", fs.file("#" <> input.root))])
  let #(blocks, root) = environment.store_tree(tree, input.store, sha256.hash)
  prepare.prepare(bundle.Bundle(root, blocks), "entry.eyg", hub, sha256.hash)
}

fn immutable(reference: ir.Reference) -> Result(v1.Cid, String) {
  case reference {
    ir.Content(cid) -> Ok(cid)
    ir.Pinned(release) -> Ok(release.module)
    _ -> Error("package acquisition requires a fully pinned reference")
  }
}

fn fetch(cid, hub, blocks) {
  let id = v1.to_string(cid)
  case store.has(blocks, id), dict.size(blocks) >= 10_000 {
    True, _ -> system.Done(Ok(blocks))
    False, True -> system.Done(Error("package module budget exhausted"))
    False, False -> {
      use module <- system.then(
        client.fetch_module(
          cid,
          hub,
          fn(request) { system.Fetch(request, _) },
          fn(algorithm, bytes) { system.Hash(algorithm, bytes, _) },
        )(system.Done),
      )
      use module <- system.try(module)
      use dependencies <- system.try(
        ir.list_references(module) |> list.map(immutable) |> result.all,
      )
      let #(blocks, actual) = store.put_node(blocks, module, sha256.hash)
      use Nil <- system.try(case actual == id {
        True -> Ok(Nil)
        False -> Error("noncanonical module identity")
      })
      system.fold(dependencies, Ok(blocks), fn(acc, dependency) {
        use blocks <- system.try(acc)
        fetch(dependency, hub, blocks)
      })
    }
  }
}
