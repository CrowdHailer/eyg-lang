//// 
//// .modules is a dict of module CID to module value and type
//// .fetching_modules is a dict of module CID to a status of NotRequested | Requested | Failed | Invalid | DependsOn(Content | Release)
//// .cursor is a number offset with a status, Pulling | Pulled | ReadyToPull
//// .releases is a dictionary of #(package, version) -> cid
//// 
//// fn module(cid) -> Unknown | Invalid(inpure/unsound) | Available(source,value,type)
//// fn release(release) -> Unknown | Invalid(incorrectmodule) | Availabile(cid)
//// 
//// fn pull(cache) -> cache : marks the cursor as ReadyToPull
//// fn fetch(cache, cid) -> cache : adds the cid to the fetching map if not yet pulled
////
//// fn flush(cache) -> #(cache, actions) -> marks the cursor as pulling and the NotRequested modules as requested.
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
import eyg/hub/release
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/list
import multiformats/cid/v1

pub type Module(meta) {
  Module(value: state.Value(meta), type_: binding.Poly)
}

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

pub type Dependency {
  Content(cid: v1.Cid)
  Release(release.Release)
}

pub type CursorStatus {
  ReadyToPull
  Pulling
  Pulled
}

pub type Action {
  FetchModule(v1.Cid)
  PullPackages(offset: Int)
}

pub type Resolution(meta) =
  #(v1.Cid, Result(state.Value(meta), state.Reason(meta)))

pub type Resource(value, reason) {
  Available(value)
  Unknown
  Unavailable(reason)
}

pub type Cache(meta) {
  Cache(
    modules: Dict(v1.Cid, Module(meta)),
    fetching_modules: Dict(v1.Cid, FetchStatus(meta)),
    releases: Dict(#(String, Int), v1.Cid),
    packages: Dict(String, #(Int, v1.Cid)),
    cursor: Int,
    cursor_status: CursorStatus,
  )
}

/// Create a new empty cache
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

/// Find a release if it is valid.
pub fn release(
  cache: Cache(meta),
  release: release.Release,
) -> Resource(v1.Cid, Nil) {
  let release.Release(package:, version:, module:) = release
  case dict.get(cache.releases, #(package, version)) {
    Ok(cid) if cid == module -> Available(module)
    Ok(_) -> Unavailable(Nil)
    Error(_) -> Unknown
  }
}

pub fn package(
  cache: Cache(meta),
  package: String,
) -> Result(#(Int, v1.Cid), Nil) {
  // dict.to_list(cache.releases)
  // |> list.filter_map(fn(entry) {
  //   let #(#(p, v), m) = entry
  //   case p == package {
  //     True -> Ok(#(v, m))
  //     False -> Error(Nil)
  //   }
  // })
  // |> list.sort(fn(r1, r2) { int.compare(pair.first(r1), pair.first(r2)) })
  // |> list.reverse
  // |> list.first
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

pub fn pull(cache: Cache(meta)) -> Cache(meta) {
  let Cache(cursor_status:, ..) = cache
  let cursor_status = case cursor_status {
    ReadyToPull -> ReadyToPull
    Pulling -> Pulling
    Pulled -> ReadyToPull
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
  }
  #(Cache(..cache, cursor_status:, fetching_modules:), effects)
}

/// Evaluates a newly arrived module and attempts to resolve anything waiting on it.
pub fn fetched(
  cache: Cache(meta),
  cid: v1.Cid,
  result: Result(ir.Node(meta), String),
) -> #(Cache(meta), List(Resolution(meta))) {
  case result {
    Ok(source) -> {
      let return = expression.execute(source, [])
      let #(cache, new) = handle_return(cache, cid, source, return)
      cascade(cache, new, [])
    }
    // transient failure
    Error(reason) -> {
      let cache = set_status(cache, cid, Failed(reason))
      #(cache, [])
    }
  }
}

/// Update the cache with the result of pulling the releases
pub fn pulled(
  cache: Cache(meta),
  cursor: Int,
  release: release.Release,
) -> #(Cache(meta), List(Resolution(meta))) {
  let release.Release(package: p, version: v, module: m) = release
  let #(unblocked, invalid) =
    dict.fold(cache.fetching_modules, #([], []), fn(acc, module, status) {
      let #(resumable, invalid) = acc
      case status {
        DependsOn(Release(dep), env, k, source)
          if dep.package == p && dep.version == v && dep.module == m
        -> #([#(module, env, k, source), ..resumable], invalid)
        DependsOn(Release(dep), ..) if dep.package == p && dep.version == v -> {
          // don't deconstruct dep as the module variable will clash with the module for the caller.
          let reason =
            break.UndefinedRelease(
              package: dep.package,
              release: dep.version,
              module: dep.module,
            )
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
  let packages = dict.insert(cache.packages, p, #(v, m))
  let cache =
    Cache(..cache, releases:, packages:, cursor:, cursor_status: Pulled)
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
      let cache = fetch(cache, m)
      let cache =
        list.fold(unblocked, cache, fn(cache, unblocked) {
          let #(module, env, k, source) = unblocked

          set_status(cache, module, DependsOn(Content(m), env:, k:, source:))
        })
      cascade(cache, invalid, [])
    }
  }
}

pub fn loop(
  return: Result(a, state.Debug(meta)),
  cache: Cache(meta),
  resume: fn(state.Value(meta), state.Env(meta), state.Stack(meta)) ->
    Result(a, state.Debug(meta)),
) -> #(Result(a, state.Debug(meta)), Cache(meta)) {
  case return {
    Error(#(break.UndefinedReference(cid), _, env, k)) -> {
      case dict.get(cache.modules, cid) {
        Ok(Module(value:, ..)) -> loop(resume(value, env, k), cache, resume)
        Error(Nil) -> #(return, fetch(cache, cid))
      }
    }
    Error(#(break.UndefinedRelease(package:, release:, module:), _meta, env, k)) -> {
      case dict.get(cache.releases, #(package, release)) {
        Ok(cid) if cid == module ->
          case dict.get(cache.modules, cid) {
            Ok(Module(value:, ..)) -> loop(resume(value, env, k), cache, resume)
            Error(Nil) -> #(return, fetch(cache, cid))
          }
        Ok(_) -> #(return, cache)
        Error(_) if release > 0 -> #(return, pull(cache))
        // Don't look for releases with invalid version number
        Error(_) -> #(return, cache)
      }
    }
    _ -> #(return, cache)
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

// Returns a list of only ever 1 or none
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
        |> infer.with_references(types(cache))
        |> infer.check(source)
        |> infer.poly_type
      let new = Module(value:, type_:)
      let modules = dict.insert(cache.modules, cid, new)
      let cache = Cache(..cache, modules:, fetching_modules:)
      #(cache, [#(cid, Ok(value))])
    }
    Error(#(break.UndefinedReference(dep), _, env, k)) ->
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
    Error(#(break.UndefinedRelease(package:, release:, module:) as r, _, env, k)) ->
      case dict.get(cache.releases, #(package, release)) {
        Ok(dep) if dep != module -> {
          let cache = set_status(cache, cid, Invalid(r))
          #(cache, [#(cid, Error(r))])
        }
        _ -> {
          let release = release.Release(package:, version: release, module:)
          let status = DependsOn(Release(release), env, k, source)
          let cache = set_status(cache, cid, status)
          #(cache, [])
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
