import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/list

// I like the always ask aproach but that means returns answer state and tasks
// message passing value ready Request(Nil, ref)

// run relies on cache, cache relies on run

// when sync message effects are to 

// If message passing then each run would keep a cache
// Solve with Sync API Yes/No/Pending

pub type Meta =
  Nil

pub type Value =
  v.Value(Meta, #(List(#(state.Kontinue(Meta), Meta)), state.Env(Meta)))

pub type Return =
  Result(Value, state.Debug(Nil))

// pub type Run {
//   Run(return: Return, effects: List(#(String, #(Value, Value))))
// }

pub fn start(exp, scope) {
  block.execute_next(exp, scope)
}

// snippets are not installed in the cache

// Need to handle effect and ref at the same time because they could be in any order
fn fetch_named_cid(cache, package, release) {
  let Cache(index: index, ..) = cache
  case dict.get(index.registry, package) {
    Ok(package_id) ->
      case dict.get(index.packages, package_id) {
        Ok(package) ->
          case dict.get(package, release) {
            Ok(release) -> Ok(release.hash)
            Error(Nil) -> Error(Nil)
          }
        Error(Nil) -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

pub fn run(return, cache, resume) {
  let Cache(fragments: fragments, ..) = cache
  case return {
    Error(#(reason, _meta, env, k)) ->
      case reason {
        break.UndefinedRelease(package, release, cid) -> {
          case fetch_named_cid(cache, package, release) {
            Ok(c) if c == cid ->
              case dict.get(fragments, cid) {
                Ok(Fragment(value: Ok(value), ..)) -> resume(value, env, k)
                _ -> return
              }
            _ -> return
          }
        }
        break.UndefinedReference(cid) -> {
          case dict.get(fragments, cid) {
            Ok(Fragment(value: Ok(value), ..)) -> resume(value, env, k)
            _ -> return
          }
        }
        _ -> return
      }
    Ok(_) -> return
  }
}

// snippet has run id or page

// can resolve ref and resolve eff be separate

// -------------------------------------

pub type Fragment {
  Fragment(source: ir.Node(Nil), value: Return)
}

pub type Release {
  Release(package_id: String, version: Int, created_at: String, hash: String)
}

pub type Index {
  Index(
    registry: Dict(String, String),
    packages: Dict(String, Dict(Int, Release)),
  )
}

pub fn index_init() {
  Index(registry: dict.new(), packages: dict.new())
}

pub type Cache {
  Cache(index: Index, fragments: Dict(String, Fragment))
}

pub fn init() {
  Cache(index: index_init(), fragments: dict.new())
}

pub fn install_fragment(cache, cid, bytes) {
  case cid.from_block(bytes) {
    c if c == cid -> {
      case dag_json.from_block(bytes) {
        // install source
        Ok(source) -> {
          let cache = install_source(cache, cid, source)
          let references = ir.list_references(source)
          let new = list.filter(references, dict.has_key(cache.fragments, _))
          // This is new references to find, it would be different to keep new resolved references
          Ok(#(cache, new))
        }
        Error(_) -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

pub fn install_source(cache, cid, source) {
  let scope = []
  let return =
    run(expression.execute_next(source, scope), cache, expression.resume)
  let fragment = Fragment(source, return)
  let fragments = dict.insert(cache.fragments, cid, fragment)
  let fragments = case return {
    Ok(value) -> resolve_references(fragments, [#(cid, value)])
    Error(_) -> fragments
  }
  Cache(..cache, fragments:)
}

pub fn resolve_references(fragments, remaining) {
  case remaining {
    [] -> fragments
    [#(cid, value), ..remaining] -> {
      let #(fragments, remaining) =
        dict.fold(fragments, #(fragments, remaining), fn(acc, key, fragment) {
          let #(fragments, new) = acc

          let Fragment(source, return) = fragment
          case return {
            Error(#(break.UndefinedReference(c), _, env, k)) if c == cid -> {
              let return = expression.resume(value, env, k)
              let fragment = Fragment(source, return)
              let fragments = dict.insert(fragments, key, fragment)
              let new = case return {
                Ok(value) -> [#(key, value), ..new]
                _ -> new
              }
              #(fragments, new)
            }
            _ -> acc
          }
        })
      resolve_references(fragments, remaining)
    }
  }
}

pub fn package_index(cache) {
  []
}
