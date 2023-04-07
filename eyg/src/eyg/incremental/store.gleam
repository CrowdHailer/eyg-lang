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
import eyg/incremental/inference
import eyg/incremental/cursor

pub type Store {
  Store(
    source: Map(Int, source.Expression),
    free: Map(Int, Set(String)),
    types: Map(Int, Map(Map(String, Scheme), t.Term)),
    substitutions: sub.Substitutions,
    counter: javascript.Reference(Int),
  )
}

pub fn empty() {
  Store(
    source: map.new(),
    free: map.new(),
    types: map.new(),
    substitutions: sub.none(),
    counter: javascript.make_reference(0),
  )
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
  use #(unresolved, store) <- result.then(do_type(map.new(), root, store))
  let t = unification.resolve(store.substitutions, unresolved)
  Ok(#(t, store))
}

// Error only for invalid ref
pub fn do_type(env, ref, store: Store) -> Result(_, _) {
  use #(vars, store) <- result.then(free(store, ref))
  let required = map.take(env, set.to_list(vars))
  case inference.cache_lookup(store.types, ref, required) {
    Ok(t) -> Ok(#(t, store))
    Error(Nil) -> {
      use node <- result.then(map.get(store.source, ref))
      use #(t, store) <- result.then(case node {
        source.Var(x) -> {
          io.debug(#(
            env
            |> map.to_list,
            x,
          ))
          case
            map.get(env, x)
            |> io.debug
          {
            Ok(scheme) -> {
              let t = unification.instantiate(scheme, store.counter)
              Ok(#(t, store))
            }
            Error(Nil) -> todo("no var in env")
          }
        }
        source.Let(x, value, then) -> {
          use #(t1, store) <- result.then(do_type(env, value, store))
          let scheme = unification.generalise(env, t1)
          let env = map.insert(env, x, scheme)
          do_type(env, then, store)
        }
        source.Fn(x, body) -> {
          let param = unification.fresh(store.counter)
          let env = map.insert(env, x, Scheme([], t.Unbound(param)))
          use #(body, store) <- result.then(do_type(env, body, store))
          let t = t.Fun(t.Unbound(param), t.Closed, body)
          Ok(#(t, store))
        }
        source.Call(func, arg) -> {
          let ret = unification.fresh(store.counter)
          use #(t1, store) <- result.then(do_type(env, func, store))
          use #(t2, store) <- result.then(do_type(env, arg, store))
          let unified =
            unification.unify(
              t.Fun(t2, t.Closed, t.Unbound(ret)),
              t1,
              store.counter,
            )
          io.debug(unified)
          let store = case unified {
            Ok(s) ->
              Store(..store, substitutions: sub.compose(store.substitutions, s))
            Error(_reason) -> {
              io.debug("unifiy failed")
              // TODO handle failure
              store
            }
          }

          Ok(#(t.Unbound(ret), store))
        }
        source.Integer(_) -> Ok(#(t.Integer, store))
        source.String(_) -> Ok(#(t.Binary, store))
        source.Tail -> Ok(#(t.tail(store.counter), store))
        source.Cons -> Ok(#(t.cons(store.counter), store))
        source.Vacant(_) ->
          Ok(#(t.Unbound(unification.fresh(store.counter)), store))
        source.Empty -> Ok(#(t.empty(), store))
        source.Extend(label) -> Ok(#(t.extend(label, store.counter), store))
        source.Select(label) -> Ok(#(t.select(label, store.counter), store))
        source.Overwrite(label) ->
          Ok(#(t.overwrite(label, store.counter), store))
        source.Tag(label) -> Ok(#(t.tag(label, store.counter), store))
        source.Case(label) -> Ok(#(t.case_(label, store.counter), store))
        source.NoCases -> Ok(#(t.nocases(store.counter), store))
        source.Perform(label) -> Ok(#(t.perform(label, store.counter), store))
        source.Handle(label) -> Ok(#(t.handle(label, store.counter), store))
        source.Builtin(_) ->
          Ok(#(t.Unbound(unification.fresh(store.counter)), store))
      })
      // TODO lookup builtins
      // Ok(#(t.builtin(store.counter), store))
      let types = inference.cache_update(store.types, ref, required, t)
      let store = Store(..store, types: types)
      Ok(#(t, store))
    }
  }
}

pub fn cursor(store: Store, root, path) {
  cursor.at_map(path, root, store.source)
}

fn do_replace(old_id, new_id, zoom, store: Store) {
  case zoom {
    [] -> Ok(#(new_id, store))
    [next, ..zoom] -> {
      use node <- result.then(map.get(store.source, next))
      let exp = case node {
        source.Let(label, value, then) if value == old_id ->
          source.Let(label, new_id, then)
        source.Let(label, value, then) if then == old_id ->
          source.Let(label, value, new_id)
        source.Fn(param, body) if body == old_id -> source.Fn(param, new_id)
        source.Call(func, arg) if func == old_id -> source.Call(new_id, arg)
        source.Call(func, arg) if arg == old_id -> source.Call(func, new_id)
        _ -> todo("Can't have a path into literal")
      }
      let new_id = map.size(store.source)
      let source = map.insert(store.source, new_id, exp)
      let store = Store(..store, source: source)
      do_replace(next, new_id, zoom, store)
    }
  }
}

// could separate pushing one item from fn and pass in new index here
pub fn replace(store: Store, cursor, exp) {
  let new_id = map.size(store.source)
  let source = map.insert(store.source, new_id, exp)
  let store = Store(..store, source: source)
  case cursor {
    #([], old) -> do_replace(old, new_id, [], store)
    #([old, ..zoom], root) ->
      do_replace(old, new_id, list.append(zoom, [root]), store)
  }
}

pub fn focus(store: Store, c) {
  map.get(store.source, cursor.inner(c))
}
