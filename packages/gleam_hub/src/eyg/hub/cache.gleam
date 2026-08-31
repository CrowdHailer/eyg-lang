//// 
//// 
//// 
//// fn fetched(cache, cid, source) -> #(cache, done) evaluates using loop the new source and adds to the set of modules if returns a value
////    Also checks all modules blocked due to a dependency and concludes them if possible, done is a list of all resolved references and releases
//// fn pulled(counter, releases) -> #(cache, done) updates the releases dict.
////    Also checks all modules blocked due to a dependency and concludes them if possible, done is a list of all resolved references and releases
//// 
//// fn loop(return,cache) -> #(return, cache) returns the updated cache with any required modules or unknown released marked as being required
//// printing errors is done based on the state of the return and the cache.
//// render reference_error (status)
//// render release_error(module,status)

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/hub/client
import eyg/hub/publisher
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/result
import midas/continuation.{type Continuation as K}
import midas/effect
import multiformats/cid/v1
import ogre/origin
import untethered/ledger/schema

/// A container for the evaluate value and inferred type of a module.
pub type Module(meta) {
  Module(value: state.Value(meta), type_: binding.Poly)
}

/// Has a module reference been requested, evaluated, failed, pending or none of the above
///
/// - `NotRequested` is equivalent to a reference not being in the collection of modules or fetching modules.
/// - `Requested` An action to request the module by it's reference has been created.
///   Requesting a module is idempotent so there is no tracking information of the request.
/// - `Failed` The request process failed and could be from a timeout, network error or bad response.
///   The failed status should be expanded with information on when the last request was made
/// - `Invalid` The content identifier has associated content but it is not a valid pure module.
///   TODO separate valid bun unsound/impure EYG code from content that is not EYG code.
/// - `DependsOn` To continue processing the module requires the dependency to be available.
pub type FetchStatus(meta) {
  NotRequested
  Requested
  Failed(String)
  Invalid(state.Reason(meta))
  DependsOn(
    dep: Dependency,
    env: state.Env(meta),
    k: state.Stack(meta),
    source: ir.Node(meta),
  )
}

/// A dependency for modules in a cache is the references that are fully specified
pub type Dependency {
  Content(cid: v1.Cid)
  Pinned(ir.Release)
}

pub fn dep_to_reason(dep: Dependency) {
  case dep {
    Content(cid:) -> break.UndefinedReference(ir.Content(cid:))
    Pinned(release) -> break.UndefinedReference(ir.Pinned(release))
  }
}

/// A cache starts with status Pulled, combined with cursor 0 this is the state
/// for a cache that has replicated an empty hub.
///
pub type CursorStatus {
  ReadyToPull
  Pulling
  Pulled
  PullFailed(String)
}

pub type Action {
  FetchModule(v1.Cid)
  PullPackages(offset: Int)
}

/// A message type for actions to return to the cache.
/// This allows callers to update the cache when actions complete without any tracking of the task on the callers side.
pub type ActionCompleted {
  FetchModuleCompleted(v1.Cid, Result(ir.Node(Nil), String))
  PullPackagesCompleted(Result(List(schema.ArchivedEntry), String))
}

pub type Resolution(meta) =
  #(v1.Cid, Result(state.Value(meta), state.Reason(meta)))

// TODO remove
pub type Resource(value, reason) {
  Available(value)
  Unknown
  Unavailable(reason)
}

/// The state of the cache.
/// It is parameterised by the metadata type of the code it stores.
/// .modules is a dict of module CID to module value and type
/// .fetching_modules is a dict of module CID to a status of NotRequested | Requested | Failed | Invalid | DependsOn(Content | Release)
/// .cursor is a number offset with a status, Pulling | Pulled | ReadyToPull | PullFailed
/// .releases is a dictionary of #(package, version) -> cid
/// .packages is a dictionary of package -> its latest entry
/// 
pub type Cache(meta) {
  Cache(
    modules: Dict(v1.Cid, Module(meta)),
    fetching_modules: Dict(v1.Cid, FetchStatus(meta)),
    releases: Dict(#(String, Int), v1.Cid),
    packages: Dict(String, Entry),
    cursor: Int,
    cursor_status: CursorStatus,
  )
}

/// A package release as it appears in the hub ledger
///
/// `version` and `module` are the public interface to the release.
/// `cid` is the identifier for the entry object, not module, in the ledger.
/// `sequence` is the position in the untethered entity which is a history over a single package.
/// `cursor` is the entry's position in the ledger, a single counter over every release on the hub
pub type Entry {
  Entry(version: Int, module: v1.Cid, cursor: Int, sequence: Int, cid: v1.Cid)
}

/// Create a new empty cache useful in tests.
/// For most situations start with a ready cache.
pub fn empty() -> Cache(meta) {
  Cache(
    modules: dict.new(),
    fetching_modules: dict.new(),
    releases: dict.new(),
    packages: dict.new(),
    cursor: 0,
    cursor_status: Pulled,
  )
}

/// Create a new cache, it is ReadyToPull
pub fn ready() -> Cache(meta) {
  Cache(
    modules: dict.new(),
    fetching_modules: dict.new(),
    releases: dict.new(),
    packages: dict.new(),
    cursor: 0,
    cursor_status: ReadyToPull,
  )
}

pub fn get_module(
  cache: Cache(meta),
  ref: v1.Cid,
) -> Result(Module(meta), FetchStatus(meta)) {
  let Cache(modules:, fetching_modules:, ..) = cache
  case dict.get(modules, ref) {
    Ok(module) -> Ok(module)
    Error(Nil) ->
      dict.get(fetching_modules, ref)
      |> result.unwrap(NotRequested)
      |> Error()
  }
}

/// Find the associated module for a cid.
pub fn module(
  cache: Cache(meta),
  cid: v1.Cid,
) -> Resource(Module(meta), state.Reason(meta)) {
  let Cache(modules:, fetching_modules:, ..) = cache
  case dict.get(modules, cid), dict.get(fetching_modules, cid) {
    Ok(module), _ -> Available(module)
    Error(Nil), Ok(NotRequested) -> Unknown
    Error(Nil), Ok(Requested) -> Unknown
    Error(Nil), Ok(DependsOn(..)) -> Unknown
    Error(Nil), Ok(Failed(_)) -> Unknown
    Error(Nil), Ok(Invalid(reason)) -> Unavailable(reason)
    Error(Nil), Error(Nil) -> Unknown
  }
}

pub fn release_code(
  cache: Cache(meta),
  release: ir.Release,
) -> Result(Module(meta), Nil) {
  let ir.Release(package:, version:, module:) = release
  case dict.get(cache.releases, #(package, version)) {
    Ok(cid) if cid == module -> dict.get(cache.modules, cid)
    _ -> Error(Nil)
  }
}

/// Find a release if it is valid.
/// TODO remove
pub fn release(
  cache: Cache(meta),
  release: ir.Release,
) -> Resource(v1.Cid, Nil) {
  let ir.Release(package:, version:, module:) = release
  case version > 0 {
    False -> Unavailable(Nil)
    True ->
      case dict.get(cache.releases, #(package, version)) {
        Ok(cid) if cid == module -> Available(module)
        Ok(_) -> Unavailable(Nil)
        Error(_) -> Unknown
      }
  }
}

pub fn unbound_release(
  cache: Cache(meta),
  package: String,
  version: Int,
) -> Result(v1.Cid, Nil) {
  dict.get(cache.releases, #(package, version))
}

/// The latest release of a package.
pub fn package(cache: Cache(meta), package: String) -> Result(Entry, Nil) {
  dict.get(cache.packages, package)
}

pub fn types(context: Cache(meta)) -> Dict(v1.Cid, binding.Poly) {
  let Cache(modules:, ..) = context
  dict.map_values(modules, fn(_key, module) { module.type_ })
}

/// Queue a cid to be fetching, if not already processing.
/// Use `flush` to get the external effect.
pub fn fetch(cache: Cache(meta), cid: v1.Cid) -> Cache(meta) {
  let Cache(modules:, fetching_modules:, ..) = cache
  case dict.get(modules, cid), dict.get(fetching_modules, cid) {
    Ok(_), Error(Nil) -> cache
    Error(Nil), Error(Nil) -> set_status(cache, cid, NotRequested)
    _, Ok(NotRequested) -> cache
    _, Ok(Requested) -> cache
    _, Ok(DependsOn(..)) -> {
      // Maybe needs to loop call to refetch failed dependency
      cache
    }
    _, Ok(Failed(_)) -> set_status(cache, cid, NotRequested)
    _, Ok(Invalid(_)) -> cache
  }
}

pub fn fetch_all(cache: Cache(meta), cids: List(v1.Cid)) -> Cache(meta) {
  list.fold(cids, cache, fetch)
}

/// Start pulling packages. Each non-empty response queues the next page, and
/// an empty response completes the pull.
pub fn pull(cache: Cache(meta)) -> Cache(meta) {
  let Cache(cursor_status:, ..) = cache
  let cursor_status = case cursor_status {
    ReadyToPull -> ReadyToPull
    Pulling -> Pulling
    Pulled -> ReadyToPull
    PullFailed(_) -> ReadyToPull
  }
  Cache(..cache, cursor_status:)
}

/// Return all the queued actions in a cache.
pub fn flush(cache: Cache(meta)) -> #(Cache(meta), List(Action)) {
  let Cache(cursor:, cursor_status:, fetching_modules:, ..) = cache
  let #(fetching_modules, effects) =
    dict.fold(fetching_modules, #(dict.new(), []), fn(acc, cid, status) {
      let #(updated, cids) = acc
      case status {
        NotRequested -> #(dict.insert(updated, cid, Requested), [
          FetchModule(cid),
          ..cids
        ])
        _ -> #(dict.insert(updated, cid, status), cids)
      }
    })

  let #(cursor_status, effects) = case cursor_status {
    ReadyToPull -> #(Pulling, [PullPackages(cursor), ..effects])
    Pulling -> #(Pulling, effects)
    Pulled -> #(Pulled, effects)
    PullFailed(reason) -> #(PullFailed(reason), effects)
  }
  #(Cache(..cache, cursor_status:, fetching_modules:), effects)
}

pub fn compute(
  action: Action,
  origin: origin.Origin,
  fetch: effect.Fetch(t),
) -> K(t, ActionCompleted) {
  case action {
    FetchModule(cid) -> {
      use result <- continuation.then(client.fetch_module(cid, origin, fetch))
      continuation.return(FetchModuleCompleted(cid, result))
    }
    PullPackages(offset:) -> {
      use result <- continuation.then(client.pull_packages(
        schema.PullParameters(since: offset, limit: 1000, entities: []),
        origin,
        fetch,
      ))
      continuation.return(PullPackagesCompleted(result))
    }
  }
}

/// Handle the `ActionCompleted` message from a finished task
pub fn update(
  cache: Cache(meta),
  message: ActionCompleted,
  map_meta: fn(Nil) -> meta,
) -> #(Cache(meta), _) {
  case message {
    FetchModuleCompleted(cid, result) -> {
      let result = result.map(result, ir.map_annotation(_, map_meta))
      fetch_module_completed(cache, cid, result)
    }
    PullPackagesCompleted(result) -> pull_packages_completed(cache, result)
  }
}

pub fn pull_packages_completed(
  cache: Cache(meta),
  result: Result(List(schema.ArchivedEntry), String),
) -> #(Cache(meta), List(Resolution(meta))) {
  case result {
    Ok(entries) -> {
      let cursor_status = case entries {
        [] -> Pulled
        _ -> ReadyToPull
      }
      let #(cache, done) =
        list.fold(entries, #(cache, []), fn(acc, entry) {
          let #(cache, done) = acc
          case json.parse(entry.payload, publisher.decoder()) {
            Ok(payload) -> {
              let publisher.Release(package:, version:, module:) =
                payload.content
              let release = ir.Release(package:, version:, module:)
              let cache = record_latest(cache, release, entry)
              let #(cache, new) = pulled(cache, entry.cursor, release)

              #(cache, list.append(done, new))
            }
            // failing to pass entry is unexpected but this fallback prevents locking the cache.
            // Better diagnostics should be added in the future.
            Error(_) -> #(Cache(..cache, cursor: entry.cursor), done)
          }
        })
      #(Cache(..cache, cursor_status:), done)
    }
    Error(reason) -> #(Cache(..cache, cursor_status: PullFailed(reason)), [])
  }
}

fn record_latest(
  cache: Cache(meta),
  release: ir.Release,
  entry: schema.ArchivedEntry,
) -> Cache(meta) {
  let ir.Release(package:, version:, module:) = release
  let schema.ArchivedEntry(cursor:, cid:, sequence:, ..) = entry
  let packages = case dict.get(cache.packages, package) {
    Ok(Entry(cursor: seen, ..)) if seen >= cursor -> cache.packages
    _ ->
      dict.insert(
        cache.packages,
        package,
        Entry(version:, module:, cursor:, sequence:, cid:),
      )
  }
  Cache(..cache, packages:)
}

/// Evaluates a newly arrived module and attempts to resolve anything waiting on it.
pub fn fetch_module_completed(
  cache: Cache(meta),
  cid: v1.Cid,
  result: Result(ir.Node(meta), String),
) -> #(Cache(meta), List(Resolution(meta))) {
  case result {
    Ok(source) -> with_module(cache, cid, source)
    // transient failure
    Error(reason) -> {
      let cache = set_status(cache, cid, Failed(reason))
      #(cache, [])
    }
  }
}

pub fn prepare(cache: Cache(meta), source: ir.Node(_)) {
  let references = ir.list_references(source)
  let cids =
    list.filter_map(references, fn(ref) {
      case ref {
        ir.Content(cid:) -> Ok(cid)
        ir.Package(..) -> Error(Nil)
        ir.Version(..) -> Error(Nil)
        ir.Pinned(release:) -> Ok(release.module)
        ir.Relative(..) -> Error(Nil)
      }
    })
  let cache = fetch_all(cache, cids)
  case list.any(references, requires_pull(cache, _)) {
    True -> pull(cache)
    False -> cache
  }
}

fn requires_pull(cache: Cache(meta), reference: ir.Reference) -> Bool {
  case reference {
    // Names its own module, or is placed by the workspace rather than the hub.
    ir.Content(..) -> False
    ir.Relative(..) -> False
    ir.Package(package:) -> result.is_error(dict.get(cache.packages, package))
    ir.Version(package:, version:) ->
      result.is_error(dict.get(cache.releases, #(package, version)))
    ir.Pinned(release:) ->
      result.is_error(
        dict.get(cache.releases, #(release.package, release.version)),
      )
  }
}

fn with_module(
  cache: Cache(meta),
  cid: v1.Cid,
  source: ir.Node(meta),
) -> #(Cache(meta), List(Resolution(meta))) {
  let return = expression.execute(source, [])
  let #(cache, new) = handle_return(cache, cid, source, return)
  cascade(cache, new, [])
}

/// Update the cache with the result of pulling the releases
pub fn pulled(
  cache: Cache(meta),
  cursor: Int,
  release: ir.Release,
) -> #(Cache(meta), List(Resolution(meta))) {
  let ir.Release(package: p, version: v, module: m) = release
  let #(unblocked, invalid) =
    dict.fold(cache.fetching_modules, #([], []), fn(acc, module, status) {
      let #(resumable, invalid) = acc
      case status {
        DependsOn(Pinned(dep), env, k, source)
          if dep.package == p && dep.version == v && dep.module == m
        -> #([#(module, env, k, source), ..resumable], invalid)
        DependsOn(Pinned(dep), ..) if dep.package == p && dep.version == v -> {
          // don't deconstruct dep as the module variable will clash with the module for the caller.
          let reason = break.UndefinedReference(ir.Pinned(dep))
          #(resumable, [#(module, Error(reason)), ..invalid])
        }
        _ -> #(resumable, invalid)
      }
    })
  let cache =
    list.fold(invalid, cache, fn(cache, reason) {
      let assert #(module, Error(reason)) = reason
      set_status(cache, module, Invalid(reason))
    })
  let releases = dict.insert(cache.releases, #(p, v), m)
  let cache = Cache(..cache, releases:, cursor:)
  // Need to handle the case of returning done releases
  case dict.get(cache.modules, m) {
    Ok(Module(value:, ..)) -> {
      let #(cache, resolved) =
        list.fold(unblocked, #(cache, []), fn(acc, unblocked) {
          let #(cache, queue) = acc
          let #(module, env, k, source) = unblocked
          let return = expression.resume(value, env, k)
          let #(cache, new) = handle_return(cache, module, source, return)
          #(cache, list.append(new, queue))
        })
      cascade(cache, list.append(resolved, invalid), [])
    }
    Error(Nil) -> {
      // Pulling a release does not require the associated module to be fetched.
      // A module might be explicitly fetch by a caller or as a dependency of one explicitly fetched.
      // If pulling a release unblocks any inprogress evaluation then it is a dependency and the module should be fetched.
      let cache = case unblocked {
        [] -> cache
        _ -> fetch(cache, m)
      }
      let cache =
        list.fold(unblocked, cache, fn(cache, unblocked) {
          let #(module, env, k, source) = unblocked

          set_status(cache, module, DependsOn(Content(m), env:, k:, source:))
        })
      cascade(cache, invalid, [])
    }
  }
}

/// Execute code in an environment with no effects implemented
pub fn loop(
  return: Result(a, state.Debug(meta)),
  cache: Cache(meta),
  resume: fn(state.Value(meta), state.Env(meta), state.Stack(meta)) ->
    Result(a, state.Debug(meta)),
) -> #(Result(a, state.Debug(meta)), Cache(meta)) {
  case return {
    Error(#(break.UndefinedReference(ir.Content(cid)), _, env, k)) -> {
      case dict.get(cache.modules, cid) {
        Ok(Module(value:, ..)) -> loop(resume(value, env, k), cache, resume)
        Error(Nil) -> #(return, fetch(cache, cid))
      }
    }
    Error(#(break.UndefinedReference(ir.Pinned(release)), _meta, env, k)) -> {
      let ir.Release(package, version, module) = release
      case dict.get(cache.releases, #(package, version)) {
        Ok(cid) if cid == module ->
          case dict.get(cache.modules, cid) {
            Ok(Module(value:, ..)) -> loop(resume(value, env, k), cache, resume)
            Error(Nil) -> #(return, fetch(cache, cid))
          }
        Ok(_) -> #(return, cache)
        Error(_) if version > 0 -> #(return, pull(cache))
        // Don't look for releases with invalid version number
        Error(_) -> #(return, cache)
      }
    }
    _ -> #(return, cache)
  }
}

/// execute code without looking up new values if not already present in the cache.
pub fn static_loop(
  return: Result(a, state.Debug(meta)),
  cache: Cache(meta),
  resume: fn(state.Value(meta), state.Env(meta), state.Stack(meta)) ->
    Result(a, state.Debug(meta)),
) -> Result(a, state.Debug(meta)) {
  case return {
    Error(#(break.UndefinedReference(ir.Content(cid)), _, env, k)) -> {
      case dict.get(cache.modules, cid) {
        Ok(Module(value:, ..)) ->
          static_loop(resume(value, env, k), cache, resume)
        Error(Nil) -> return
      }
    }
    Error(#(break.UndefinedReference(ir.Package(package)), _meta, env, k)) ->
      case dict.get(cache.packages, package) {
        Ok(Entry(module:, ..)) ->
          case dict.get(cache.modules, module) {
            Ok(Module(value:, ..)) ->
              static_loop(resume(value, env, k), cache, resume)
            Error(Nil) -> return
          }
        Error(Nil) -> return
      }
    Error(#(break.UndefinedReference(ir.Version(package, version)), _m, env, k)) ->
      case dict.get(cache.releases, #(package, version)) {
        Ok(cid) ->
          case dict.get(cache.modules, cid) {
            Ok(Module(value:, ..)) ->
              static_loop(resume(value, env, k), cache, resume)
            Error(Nil) -> return
          }
        Error(Nil) -> return
      }
    Error(#(break.UndefinedReference(ir.Pinned(release)), _meta, env, k)) -> {
      let ir.Release(package, version, module) = release
      case dict.get(cache.releases, #(package, version)) {
        Ok(cid) if cid == module ->
          case dict.get(cache.modules, cid) {
            Ok(Module(value:, ..)) ->
              static_loop(resume(value, env, k), cache, resume)
            Error(Nil) -> return
          }
        _ -> return
      }
    }
    _ -> return
  }
}

/// Find all the in progress modules that are blocked by a specific cid.
fn blocked_by(fetching_modules, resolved_cid) {
  dict.fold(fetching_modules, [], fn(resumable, module, status) {
    case status {
      DependsOn(Content(dep), env, k, source) if dep == resolved_cid -> {
        [#(module, env, k, source), ..resumable]
      }
      _ -> resumable
    }
  })
}

/// When the evaluation of a module is unblocked by the return of a cid
/// Only ever resolves 1 or none, so returns a list that is flat mapped over
fn handle_return(
  cache: Cache(meta),
  cid: v1.Cid,
  source: ir.Node(meta),
  return: Result(state.Value(meta), state.Debug(meta)),
) -> #(Cache(meta), List(Resolution(meta))) {
  let #(return, cache) = loop(return, cache, expression.resume)
  case return {
    Ok(value) -> {
      // The cid doesn't need removing from fetching modules because it was cleared when taking all unblocked modules
      let fetching_modules = dict.delete(cache.fetching_modules, cid)
      let type_ =
        infer.pure()
        |> infer.check_with_references(types(cache), source)
        |> infer.poly_type
      let new = Module(value:, type_:)
      let modules = dict.insert(cache.modules, cid, new)
      let cache = Cache(..cache, modules:, fetching_modules:)
      #(cache, [#(cid, Ok(value))])
    }
    Error(#(break.UndefinedReference(ir.Content(dep)), _, env, k)) ->
      case dict.get(cache.fetching_modules, dep) {
        Ok(Invalid(reason)) -> {
          let cache = set_status(cache, cid, Invalid(reason))
          #(cache, [#(cid, Error(reason))])
        }
        _ -> {
          let status = DependsOn(Content(dep), env, k, source)
          let cache = set_status(cache, cid, status)
          #(cache, [])
        }
      }
    Error(#(break.UndefinedReference(ir.Pinned(release)) as r, _, env, k)) -> {
      let ir.Release(package, version, module) = release
      case dict.get(cache.releases, #(package, version)) {
        Ok(dep) if dep != module -> {
          let cache = set_status(cache, cid, Invalid(r))
          #(cache, [#(cid, Error(r))])
        }
        Ok(dep) ->
          case dict.get(cache.fetching_modules, dep) {
            Ok(Invalid(reason)) -> {
              let cache = set_status(cache, cid, Invalid(reason))
              #(cache, [#(cid, Error(reason))])
            }
            _ -> {
              let status = DependsOn(Content(dep), env:, k:, source:)
              #(set_status(cache, cid, status), [])
            }
          }
        Error(Nil) -> {
          let status = DependsOn(Pinned(release), env, k, source)
          let cache = set_status(cache, cid, status)
          #(cache, [])
        }
      }
    }
    Error(#(reason, _, _, _)) -> {
      let cache = set_status(cache, cid, Invalid(reason))
      #(cache, [#(cid, Error(reason))])
    }
  }
}

/// queue is resolutions that need to be cascaded
/// done is the resolutions that have been cascaded to return to the caller
fn cascade(
  cache: Cache(meta),
  queue: List(Resolution(meta)),
  done: List(Resolution(meta)),
) {
  case queue {
    [] -> #(cache, done)
    [#(resolved_cid, result), ..rest_queue] -> {
      let to_resume = blocked_by(cache.fetching_modules, resolved_cid)
      // remaining is the outstanding queue of resolved modules
      let #(cache, remaining) =
        list.fold(to_resume, #(cache, rest_queue), fn(acc, item) {
          let #(cache, q) = acc
          // cid here is the dependent cid associated with the env and k to finish evaluating source
          // The result is the value (or failure) of the dependency, associated with recolved_cid
          let #(cid, env, k, source) = item
          case result {
            // This is the dependency value
            Ok(value) -> {
              let return = expression.resume(value, env, k)
              let #(cache, new) = handle_return(cache, cid, source, return)
              #(cache, list.append(new, q))
            }
            Error(reason) -> {
              let cache = set_status(cache, cid, Invalid(reason))
              #(cache, [#(cid, Error(reason)), ..q])
            }
          }
        })
      cascade(cache, remaining, [#(resolved_cid, result), ..done])
    }
  }
}

fn set_status(
  cache: Cache(meta),
  cid: v1.Cid,
  status: FetchStatus(meta),
) -> Cache(meta) {
  let fetching_modules = dict.insert(cache.fetching_modules, cid, status)
  Cache(..cache, fetching_modules:)
}
