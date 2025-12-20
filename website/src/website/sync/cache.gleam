import eyg/analysis/type_/binding
import eyg/interpreter/break
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/list

pub type Cache {
  Cache(
    releases: Dict(#(String, Int), Release),
    fragments: Dict(String, Fragment),
  )
}

pub type Fragment {
  Fragment(source: ir.Node(Nil), value: Value, type_: binding.Poly)
}

pub type Release {
  Release(package_id: String, version: Int, created_at: String, cid: String)
}

pub type Meta =
  Nil

pub type Value =
  v.Value(Meta, #(List(#(state.Kontinue(Meta), Meta)), state.Env(Meta)))

pub fn init() {
  Cache(releases: dict.new(), fragments: dict.new())
}

// pub fn start(exp, scope) {
//   block.execute(exp, scope)
// }

pub fn run(return, cache, resume) {
  let Cache(releases:, fragments:) = cache
  case return {
    Error(#(break.UndefinedRelease(package, version, cid), _meta, env, k)) ->
      case dict.get(releases, #(package, version)) {
        Ok(release) if release.cid == cid ->
          case dict.get(fragments, cid) {
            Ok(Fragment(value:, ..)) -> resume(value, env, k)
            _ -> return
          }
        _ -> return
      }
    Error(#(break.UndefinedReference(cid), _meta, env, k)) ->
      case dict.get(fragments, cid) {
        Ok(Fragment(value:, ..)) -> resume(value, env, k)
        _ -> return
      }
    _ -> return
  }
}

// pub fn max_release(cache, package) {
//   let Cache(index: index, ..) = cache
//   case dict.get(index.registry, package) {
//     Ok(package_id) ->
//       case dict.get(index.packages, package_id) {
//         Ok(package) -> {
//           case dict.size(package) {
//             0 -> Error(Nil)
//             n -> Ok(n)
//           }
//         }

//         Error(Nil) -> Error(Nil)
//       }
//     Error(Nil) -> Error(Nil)
//   }
// }

// pub fn fetch_fragment(cache: Cache, cid) {
//   dict.get(cache.fragments, cid)
// }

// // Fragment is a cache of the computed value
// fn create_fragment(source, return, types) {
//   let #(type_, errors) = fragment.infer(source, types)
//   Fragment(source, return, type_, errors)
// }

// pub fn set_index(cache, index) {
//   // In the future this could merge or roll forward
//   Cache(..cache, index:)
// }

// // decide whether to remove this or not when the error messages for still loading refs is decided
// pub fn install_fragment(cache, cid, bytes) {
//   case dag_json.from_block(bytes) {
//     // install source
//     Ok(source) -> {
//       let cache = install_source(cache, cid, source)
//       let references = ir.list_references(source)
//       let required = list.filter(references, dict.has_key(cache.fragments, _))
//       // This is required references to find, it would be different to keep new resolved references
//       Ok(#(cache, required))
//     }
//     Error(_) -> Error(Nil)
//   }
// }

// // This assumes the cid is valid, this module could be internal or a block as an opaque type used for a safer API
// pub fn install_source(cache, cid, source) {
//   let scope = []
//   let return = run(expression.execute(source, scope), cache, expression.resume)
//   let fragment = create_fragment(source, return, type_map(cache))
//   let fragments = dict.insert(cache.fragments, cid, fragment)
//   let fragments = case return {
//     Ok(value) -> resolve_references(fragments, [#(cid, value)])
//     Error(_) -> fragments
//   }
//   Cache(..cache, fragments:)
// }

// pub fn resolve_references(fragments, remaining) {
//   case remaining {
//     [] -> fragments
//     [#(cid, value), ..remaining] -> {
//       let #(fragments, remaining) =
//         dict.fold(fragments, #(fragments, remaining), fn(acc, key, fragment) {
//           let #(fragments, new) = acc

//           let Fragment(source, return, _, errors) = fragment
//           case return {
//             Error(#(break.UndefinedReference(c), _, env, k)) if c == cid -> {
//               let return = expression.resume(value, env, k)
//               let fragment =
//                 create_fragment(source, return, do_type_map(fragments))
//               let fragments = dict.insert(fragments, key, fragment)
//               let new = case return {
//                 Ok(value) -> [#(key, value), ..new]
//                 _ -> new
//               }
//               #(fragments, new)
//             }
//             _ ->
//               case errors {
//                 [] -> acc
//                 _ -> {
//                   let fragment =
//                     create_fragment(source, return, do_type_map(fragments))
//                   let fragments = dict.insert(fragments, key, fragment)
//                   let new = case fragment.errors {
//                     [] -> [#(key, value), ..new]
//                     _ -> new
//                   }
//                   #(fragments, new)
//                 }
//               }
//           }
//         })
//       resolve_references(fragments, remaining)
//     }
//   }
// }

pub fn type_map(cache) {
  let Cache(fragments:, ..) = cache
  do_type_map(fragments)
}

fn do_type_map(fragments) {
  fragments
  |> dict.to_list()
  |> list.map(fn(e: #(String, Fragment)) {
    let #(k, fragment) = e
    #(k, fragment.type_)
  })
  |> dict.from_list()
}

pub fn package_index(cache) {
  echo "todo find the latest for each package"
  []
}
