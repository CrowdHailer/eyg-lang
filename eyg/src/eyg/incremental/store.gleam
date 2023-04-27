import gleam/io
import gleam/list
import gleam/map.{Map}
import gleam/result
import gleam/set.{Set}
import gleam/setx
import gleam/javascript
// TODO source -> ref
import eyg/analysis/typ as t
import eyg/analysis/substitutions as sub
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/unification
import eyg/incremental/source
import eyg/analysis/env
import eyg/incremental/inference
import eyg/incremental/cursor
import plinth/javascript/map as mutable_map

pub type Store {
  Store(
    source: Map(Int, source.Expression),
    // Not used. do map size instead
    source_id_tracker: javascript.Reference(Int),
    free: Map(Int, Set(String)),
    free_mut: mutable_map.MutableMap(Int, Set(String)),
    types: Map(Int, Map(Map(String, Scheme), t.Term)),
    substitutions: sub.Substitutions,
    counter: javascript.Reference(Int),
  )
}

pub fn empty() {
  Store(
    source: map.new(),
    source_id_tracker: javascript.make_reference(0),
    free: map.new(),
    free_mut: mutable_map.new(),
    types: map.new(),
    substitutions: sub.none(),
    counter: javascript.make_reference(0),
  )
}

pub fn load(store: Store, tree) {
  let #(index, source) =
    source.do_from_tree_map(tree, store.source, store.source_id_tracker)
  #(index, Store(..store, source: source))
}

pub fn free(store: Store, root) -> Result(#(Set(String), Store), Nil) {
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

pub fn free_mut(store: Store, root) -> Result(#(Set(String), Store), Nil) {
  case mutable_map.get(store.free_mut, root) {
    Ok(vars) -> Ok(#(vars, store))
    Error(Nil) -> {
      use node <- result.then(map.get(store.source, root))
      use #(vars, store) <- result.then(case node {
        source.Var(x) -> Ok(#(setx.singleton(x), store))
        source.Fn(x, ref) -> {
          use #(vars, store) <- result.then(free_mut(store, ref))
          Ok(#(set.delete(vars, x), store))
        }
        source.Let(x, ref_v, ref_t) -> {
          use #(value, store) <- result.then(free_mut(store, ref_v))
          use #(then, store) <- result.then(free_mut(store, ref_t))
          let vars = set.union(value, set.delete(then, x))
          Ok(#(vars, store))
        }
        source.Call(ref_func, ref_arg) -> {
          use #(func, store) <- result.then(free_mut(store, ref_func))
          use #(arg, store) <- result.then(free_mut(store, ref_arg))
          let vars = set.union(func, arg)
          Ok(#(vars, store))
        }
        _ -> Ok(#(set.new(), store))
      })
      let free = mutable_map.set(store.free_mut, root, vars)
      // let store = Store(..store, free: free)
      Ok(#(vars, store))
    }
  }
}

pub fn cursor(store: Store, root, path) {
  cursor.at(path, root, store.source)
}

// Move to source or cursor

// could separate pushing one item from fn and pass in new index here
pub fn replace(source, cursor, exp) {
  let new_id = map.size(source)
  let source = map.insert(source, new_id, exp)
  source.replace(source, cursor, new_id)
}

pub fn focus(store: Store, c) {
  map.get(store.source, cursor.inner(c))
}

// used for debugging maps. there should be only one reference to a node in a store with a single root.
pub fn ref_group(store: Store) {
  let child_refs =
    list.flat_map(
      map.to_list(store.source),
      fn(entry) {
        let #(_ref, node) = entry
        case node {
          // source.Var(String)
          source.Fn(_, child) -> [#(child, entry)]
          source.Let(_, c1, c2) -> [#(c1, entry), #(c2, entry)]
          source.Call(c1, c2) -> [#(c1, entry), #(c2, entry)]
          _ -> []
        }
      },
    )
  child_refs
  |> list.group(fn(x) { x.0 })
  |> map.filter(fn(_, v) { list.length(v) < 1 })
}
