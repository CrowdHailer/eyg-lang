//// Drive inference without waiting for IO. Missing references are recorded and
//// queued, then inference continues so independent dependencies load together.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/cache
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/set
import loam/source
import loam/system

pub type FileKey =
  #(source.Origin, String)

pub type File {
  Reading(task_id: Int)
  Read(module: ir.Node(source.Location), loading: Bool)
  Unreadable(String)
}

pub type Dependency {
  Hub(ir.Reference)
  Import(FileKey)
}

pub type Tracking {
  Tracking(
    cache: cache.Cache(source.Location),
    files: dict.Dict(FileKey, File),
    counter: Int,
    previous: set.Set(Dependency),
    dependencies: set.Set(Dependency),
    reads: List(#(FileKey, Int)),
  )
}

pub fn check(
  step: infer.Step(a),
  cache,
  files,
  counter,
  previous,
  retry: Bool,
) {
  let tracking = Tracking(cache, files, counter, previous, set.new(), [])
  let #(checked, tracking, _) =
    loop(step, source.Repl, [], tracking, retry, False)
  #(checked, tracking)
}

fn loop(
  step: infer.Step(a),
  origin: source.Origin,
  visiting: List(source.Origin),
  tracking: Tracking,
  retry: Bool,
  waiting: Bool,
) -> #(a, Tracking, Bool) {
  case step {
    infer.Done(value) -> #(value, tracking, waiting)
    infer.Lookup(reference, resume) -> {
      let #(answer, tracking, loading) = case reference {
        ir.Relative(location) ->
          file(#(origin, location), visiting, tracking, retry)
        _ -> hub(reference, tracking, retry)
      }
      loop(
        resume(answer),
        origin,
        visiting,
        tracking,
        retry,
        waiting || loading,
      )
    }
  }
}

fn hub(reference, tracking: Tracking, retry) {
  // A file arriving can reveal a reference for the first time. Queue it even
  // during an IO update, but do not repeatedly pull a known missing release.
  let retry = retry || !set.contains(tracking.previous, Hub(reference))
  let cache = request(tracking.cache, reference, retry)
  let answer = case cache.get_reference(cache, reference) {
    Ok(module) -> Ok(module.type_)
    Error(Nil) -> Error(Nil)
  }
  let tracking =
    Tracking(
      ..tracking,
      cache:,
      dependencies: set.insert(tracking.dependencies, Hub(reference)),
    )
  #(answer, tracking, cache.reference_in_progress(cache, reference))
}

fn request(cache, reference, retry) {
  case reference {
    ir.Content(cid) -> request_module(cache, cid, retry)
    ir.Package(name) ->
      case cache.package(cache, name) {
        Ok(entry) -> request_module(cache, entry.module, retry)
        Error(_) -> request_releases(cache, retry)
      }
    ir.Version(name, version) ->
      case cache.unbound_release(cache, name, version) {
        Ok(cid) -> request_module(cache, cid, retry)
        Error(_) -> request_releases(cache, retry)
      }
    ir.Pinned(release) ->
      case cache.unbound_release(cache, release.package, release.version) {
        Ok(cid) if cid != release.module -> cache
        Ok(cid) -> request_module(cache, cid, retry)
        Error(_) ->
          cache
          |> request_releases(retry)
          |> request_module(release.module, retry)
      }
    ir.Relative(_) -> cache
  }
}

fn request_releases(cache, retry) {
  case retry {
    True -> cache.pull(cache)
    False -> cache
  }
}

fn request_module(cache, cid, retry) {
  case cache.get_module(cache, cid) {
    Error(cache.NotRequested) -> cache.fetch(cache, cid)
    Error(_) if retry -> cache.fetch(cache, cid)
    _ -> cache
  }
}

fn file(key, visiting, tracking: Tracking, retry) {
  let tracking =
    Tracking(
      ..tracking,
      dependencies: set.insert(tracking.dependencies, Import(key)),
    )
  case dict.get(tracking.files, key) {
    Ok(Reading(_)) -> #(Error(Nil), tracking, True)
    Ok(Unreadable(_)) if !retry -> #(Error(Nil), tracking, False)
    Ok(Read(module, _)) -> {
      // The resolved origin is an absolute file path. It catches cycles even
      // when the same file was imported using different relative spellings.
      let origin = module.1.origin
      case list.contains(visiting, origin) {
        True -> #(Error(Nil), tracking, False)
        False -> {
          let #(analysis, tracking, loading) =
            loop(
              infer.check(infer.pure(), module),
              origin,
              [origin, ..visiting],
              tracking,
              retry,
              False,
            )
          let answer = case infer.all_errors(analysis) {
            [] -> Ok(infer.poly_type(analysis))
            _ -> Error(Nil)
          }
          let files = dict.insert(tracking.files, key, Read(module, loading))
          #(answer, Tracking(..tracking, files:), loading)
        }
      }
    }
    _ -> {
      let id = tracking.counter
      let tracking =
        Tracking(
          ..tracking,
          counter: id + 1,
          files: dict.insert(tracking.files, key, Reading(id)),
          reads: [#(key, id), ..tracking.reads],
        )
      #(Error(Nil), tracking, True)
    }
  }
}

pub fn loading(files, cache, reference) {
  case reference {
    ir.Relative(location) ->
      case dict.get(files, #(source.Repl, location)) {
        Ok(Reading(_)) -> True
        Ok(Read(_, loading)) -> loading
        _ -> False
      }
    _ -> cache.reference_in_progress(cache, reference)
  }
}

pub fn read(key: FileKey) {
  let #(origin, location) = key
  use path <- system.then(source.resolve_filepath(origin, location))
  case path {
    Error(reason) -> system.Done(Error(reason))
    Ok(path) -> {
      use code <- system.map(system.read_file(path))
      case code {
        Ok(code) -> source.parse(code, source.Disk(path))
        Error(_) -> Error("failed to read module from location: " <> location)
      }
    }
  }
}
