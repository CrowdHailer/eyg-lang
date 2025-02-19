import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}

pub fn fetch_sync() {
  todo
}

// THe promise version needs a ref
pub fn fetch_async() {
  todo
}

// unknown at time or data
// Error Unknown/UnknownFragMent/Avaiting
// sync has to have the stateful run but it's pure and without scope
pub fn fetch_registration() {
  todo
}

// there is a sync run and that can be used by the editor 
pub fn run_and_catch_promises() -> Nil {
  case todo {
    break.UnhandledEffect(label, value) -> todo
    break.UndefinedReference(ref) -> todo
    _ -> todo
  }
}

// Needto separetlytype check all the refs even if they were not evaluated

// The list of snippets all snippets currently use the block runner

// render snippet takes cache as an argument to show loading or errored

// I like the always ask aproach but that means returns answer state and tasks
// message passing value ready Request(Nil, ref)

// use #(value,type) <- lookupref

// run relies on cache, cache relies on run
// never waiting on effect in cache so can show as error

// when sync message effects are to 

// If message passing then each run would keep a cache
// Solve with Sync API Yes/No/Pending

// importantly the run state does not include a hash
// run continue with cache
// run continue with effect

pub type Meta =
  Nil

pub type Value =
  v.Value(Meta, #(List(#(state.Kontinue(Meta), Meta)), state.Env(Meta)))

pub type Return =
  Result(Value, state.Debug(Nil))

pub type Run {
  Run(return: Return, effects: List(#(String, #(Value, Value))))
}

pub fn start(exp, scope) {
  block.execute_next(exp, scope)
}

// Need to handle effect and ref at the same time because they could be in any order
pub fn act(return, cache) {
  case return {
    Error(#(reason, _meta, env, k)) ->
      case reason {
        break.UndefinedReference(cid) -> {
          let Cache(fragments: fragments) = cache
          case dict.get(fragments, cid) {
            Ok(Fragment(value: Ok(value), ..)) ->
              expression.resume(value, env, k)
            _ -> return
          }
        }
        _ -> return
      }
    Ok(_) -> return
  }
}

// can resolve ref and resolve eff be separate

// -------------------------------------

pub type Fragment {
  Fragment(source: ir.Node(Nil), value: Return)
}

pub type Cache {
  Cache(fragments: Dict(String, Fragment))
}

pub fn init() {
  Cache(dict.new())
}

pub fn install_fragment(cache, cid, bytes) {
  case cid.from_block(bytes) {
    c if c == cid -> {
      case dag_json.from_block(bytes) {
        Ok(source) -> {
          let scope = []
          let return = act(expression.execute_next(source, scope), cache)
          let fragment = Fragment(source, return)
          let fragments = dict.insert(cache.fragments, cid, fragment)
          case return {
            Ok(value) ->
              resolve_references(fragments, [#(cid, value)]) |> Cache |> Ok
            Error(_) -> Ok(cache)
          }
        }
        Error(_) -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn resolve_references(fragments, remaining) {
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
              let fragments = dict.insert(fragments, cid, fragment)
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
// Fetch tasks are different promises
