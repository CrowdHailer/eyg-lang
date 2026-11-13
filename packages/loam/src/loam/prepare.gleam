//// Lock an entry program against an acquired filesystem, before execution.

import eyg/hub/cache
import filepath
import glasshouse/bundle
import glasshouse/lock
import glasshouse/recorder
import glasshouse/store
import gleam/dict
import gleam/option
import gleam/result
import loam/broker
import loam/environment
import loam/execute
import loam/pin
import loam/sandbox/fs
import loam/source
import loam/system
import loam/virtual
import ogre/origin

/// Start without a project snapshot: only the explicitly supplied configuration
/// and its code dependencies are present. Relative host imports are unavailable.
pub fn configuration(
  code: String,
  origin: origin.Origin,
  sha256: store.Sha256,
) -> system.Effect(Result(bundle.Bundle, String)) {
  let tree = fs.directory([#(".overlay.eyg", fs.file(code))])
  let #(blocks, root) = environment.store_tree(tree, store.new(), sha256)
  prepare(bundle.new(root, blocks), ".overlay.eyg", origin, sha256)
}

pub fn prepare(
  input: bundle.Bundle,
  entry: String,
  origin: origin.Origin,
  sha256: store.Sha256,
) -> system.Effect(Result(bundle.Bundle, String)) {
  use tree <- system.try(environment.tree(input))
  let environment =
    environment.Environment(
      ..environment.new(),
      files: fs.directory([#("workspace", tree)]),
      store: input.store,
      hub: origin,
    )
  let path = filepath.join(environment.cwd, entry)
  use code <- system.try(
    fs.read(environment.files, path)
    |> result.replace_error("entry is not in the acquired tree: " <> entry),
  )
  use node <- system.try(source.parse(code, source.Disk(path)))
  let recorder = recorder.new(sha256) |> recorder.with_store(environment.store)
  let program =
    pin.pin(
      node,
      environment.cwd,
      execute.State(origin, cache.empty(), option.None),
      recorder,
      pin.allow,
    )
  let machine =
    virtual.fork(environment) |> virtual.with_broker(broker.Live([origin.host]))
  use #(pinned, _) <- system.map(virtual.run(program, machine))
  use #(pinned, _, recorder) <- result.try(pinned)
  use pinned <- result.try(pinned)
  // Secret imports deliberately have no stored blocks. Such a closure cannot
  // become a portable environment; credentials belong at the external boundary.
  use Nil <- result.try(
    case
      dict.size(pinned.lock.secrets) == 0
      && store.missing(recorder.store(recorder), lock.references(pinned.lock))
      == []
    {
      True -> Ok(Nil)
      False -> Error("environment contains unstored secret imports")
    },
  )
  Ok(environment.seal(
    environment.Environment(
      ..environment,
      lock: pinned.lock,
      programs: dict.from_list([#(path, pinned.program)]),
      store: recorder.store(recorder),
    ),
    sha256,
  ))
}
