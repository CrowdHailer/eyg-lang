import gleam/map.{Map}
import gleam/result
import gleam/set.{Set}
import gleam/setx
// TODO source -> ref
import eyg/incremental/source
import eyg/incremental/inference

pub type Store {
  Store(source: Map(Int, source.Expression), free: Map(Int, Set(String)))
}

pub fn empty() {
  Store(source: map.new(), free: map.new())
}

pub fn load(store: Store, tree) {
  let #(exp, acc) = source.do_from_tree_map(tree, store.source)
  let index = map.size(acc)
  let source = map.insert(acc, index, exp)
  #(index, Store(..store, source: source))
}

pub fn free(store: Store, root) {
  case map.get(store.free, root) {
    Ok(vars) -> Ok(#(vars, store))
    Error(Nil) -> {
      use node <- result.then(map.get(store.source, root))
      use #(vars, store) <- result.then(case node {
        source.Var(x) -> Ok(#(setx.singleton(x), store))
        source.Fn(x, ref) -> {
          use #(vars, store) <- result.then(free(store, ref))
          Ok(#(set.delete(vars, x), store))
        }
        source.Let(x, ref_v, ref_t) -> {
          use #(value, store) <- result.then(free(store, ref_v))
          use #(then, store) <- result.then(free(store, ref_t))
          let vars = set.union(value, set.delete(then, x))
          Ok(#(vars, store))
        }
        source.Call(ref_func, ref_arg) -> {
          use #(func, store) <- result.then(free(store, ref_func))
          use #(arg, store) <- result.then(free(store, ref_arg))
          let vars = set.union(func, arg)
          Ok(#(vars, store))
        }
        _ -> Ok(#(set.new(), store))
      })
      let free = map.insert(store.free, root, vars)
      let store = Store(..store, free: free)
      Ok(#(vars, store))
    }
  }
}

pub fn type_(store: Store, root) {
  //   inference.cached(root, store.source, f, cache, env.empty(), s, count)
  todo("do type")
}
// pub fn do_type(store: Store, ref) {
//   let assert Ok(free) = list.at(frees, ref)
//   let required = map.take(env, set.to_list(free))
//   case cache_lookup(types, ref, required) {
//     Ok(t) -> #(t, subs, types)
//     Error(Nil) -> {
//       let assert Ok(node) = list.at(source, ref)
//       let #(t, subs, cache) = case node {
//         source.Var(x) ->
//           case map.get(env, x) {
//             Ok(scheme) -> {
//               let t = unification.instantiate(scheme, count)
//               #(t, subs, types)
//             }
//             Error(Nil) -> todo("no var")
//           }
//         source.Let(x, value, then) -> {
//           let #(t1, subs, types) =
//             cached(value, source, frees, types, env, subs, count)
//           let scheme = unification.generalise(env, t1)
//           let env = map.insert(env, x, scheme)
//           cached(then, source, frees, types, env, subs, count)
//         }
//         source.Fn(x, body) -> {
//           let param = unification.fresh(count)
//           let env = map.insert(env, x, Scheme([], t.Unbound(param)))
//           let #(body, subs, types) =
//             cached(body, source, frees, types, env, subs, count)
//           let t = t.Fun(t.Unbound(param), t.Closed, body)
//           #(t, subs, types)
//         }
//         source.Call(func, arg) -> {
//           let ret = unification.fresh(count)
//           let #(t1, s1, types) =
//             cached(func, source, frees, types, env, subs, count)
//           let #(t2, s2, types) =
//             cached(arg, source, frees, types, env, subs, count)
//           let s0 =
//             unification.unify(t.Fun(t2, t.Closed, t.Unbound(ret)), t1, count)
//           #(t.Unbound(ret), s1, types)
//         }
//         source.Integer(_) -> #(t.Integer, subs, types)
//         source.String(_) -> #(t.Binary, subs, types)
//         _ -> #(t.Unbound(unification.fresh(count)), subs, types)
//       }
//       let cache = cache_update(cache, ref, required, t)
//       #(t, subs, cache)
//     }
//   }
// }
