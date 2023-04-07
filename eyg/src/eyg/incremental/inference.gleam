import gleam/io
import gleam/list
import gleam/map.{Map}
import gleam/option
import gleam/result
import gleam/set.{Set}
import gleam/setx
import gleam/javascript
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/analysis/substitutions as sub
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/env
import eyg/analysis/unification
import eyg/incremental/source
import eyg/incremental/cursor

pub type Cache =
  #(sub.Substitutions, Map(Int, Map(Map(String, Scheme), t.Term)))

fn from_end(items, i) {
  list.at(items, list.length(items) - 1 - i)
}

fn do_free(rest, acc) {
  case rest {
    [] -> list.reverse(acc)
    [node, ..rest] -> {
      let free = case node {
        source.Var(x) -> setx.singleton(x)
        source.Fn(x, ref) -> {
          let assert Ok(body) = from_end(acc, ref)
          set.delete(body, x)
        }
        source.Let(x, ref_v, ref_t) -> {
          let assert Ok(value) = from_end(acc, ref_v)
          let assert Ok(then) = from_end(acc, ref_t)
          set.union(value, set.delete(then, x))
        }
        source.Call(ref_func, ref_arg) -> {
          let assert Ok(func) = from_end(acc, ref_func)
          let assert Ok(arg) = from_end(acc, ref_arg)
          set.union(func, arg)
        }
        _ -> set.new()
      }
      do_free(rest, [free, ..acc])
    }
  }
}

pub fn free(refs, previous) {
  do_free(list.drop(refs, list.length(previous)), list.reverse(previous))
}

fn do_free_map(rest, acc) {
  case rest {
    [] -> acc
    [node, ..rest] -> {
      let free = case node {
        source.Var(x) -> setx.singleton(x)
        source.Fn(x, ref) -> {
          let assert Ok(body) = map.get(acc, ref)
          set.delete(body, x)
        }
        source.Let(x, ref_v, ref_t) -> {
          let assert Ok(value) = map.get(acc, ref_v)
          let assert Ok(then) = map.get(acc, ref_t)
          set.union(value, set.delete(then, x))
        }
        source.Call(ref_func, ref_arg) -> {
          let assert Ok(func) = map.get(acc, ref_func)
          let assert Ok(arg) = map.get(acc, ref_arg)
          set.union(func, arg)
        }
        _ -> set.new()
      }
      do_free_map(rest, map.insert(acc, map.size(acc), free))
    }
  }
}

pub fn free_map(refs, previous) {
  // TODO need to be careful on taking new only
  do_free_map(list.drop(refs, map.size(previous)), previous)
}

// // Need single map of substitutions, is this the efficient J algo?
// // Free should be easy in bottom up order assume need value is already present
// // probably not fast in edits to std lib. maybe with only part of record field it would be faster.
// // but if async and cooperative then we can just manage without as needed.
// // TODO have building type stuff happen at startup. try it out in browser

// TODO test calling the same node twice hits the cach

pub fn cache_lookup(cache, ref, env) {
  use envs <- result.then(map.get(cache, ref))

  map.get(envs, env)
}

pub fn cache_update(cache, ref, env, t) {
  map.update(
    cache,
    ref,
    fn(cached) {
      option.unwrap(cached, map.new())
      |> map.insert(env, t)
    },
  )
}

// frees can  be built lazily as a map
// hash cache can exist for saving to file
pub fn cached(
  ref: Int,
  source,
  frees,
  types,
  env,
  subs: sub.Substitutions,
  count,
) {
  let assert Ok(free) = list.at(frees, ref)
  let required = map.take(env, set.to_list(free))
  case cache_lookup(types, ref, required) {
    Ok(t) -> #(t, subs, types)
    Error(Nil) -> {
      let assert Ok(node) = list.at(source, ref)
      let #(t, subs, cache) = case node {
        source.Var(x) ->
          case map.get(env, x) {
            Ok(scheme) -> {
              let t = unification.instantiate(scheme, count)
              #(t, subs, types)
            }
            Error(Nil) -> todo("no var")
          }
        source.Let(x, value, then) -> {
          let #(t1, subs, types) =
            cached(value, source, frees, types, env, subs, count)
          let scheme = unification.generalise(env, t1)
          let env = map.insert(env, x, scheme)
          cached(then, source, frees, types, env, subs, count)
        }
        source.Fn(x, body) -> {
          let param = unification.fresh(count)
          let env = map.insert(env, x, Scheme([], t.Unbound(param)))
          let #(body, subs, types) =
            cached(body, source, frees, types, env, subs, count)
          let t = t.Fun(t.Unbound(param), t.Closed, body)
          #(t, subs, types)
        }
        source.Call(func, arg) -> {
          let ret = unification.fresh(count)
          let #(t1, s1, types) =
            cached(func, source, frees, types, env, subs, count)
          let #(t2, s2, types) =
            cached(arg, source, frees, types, env, subs, count)
          let s0 =
            unification.unify(t.Fun(t2, t.Closed, t.Unbound(ret)), t1, count)
          #(t.Unbound(ret), s1, types)
        }
        source.Integer(_) -> #(t.Integer, subs, types)
        source.String(_) -> #(t.Binary, subs, types)
        _ -> #(t.Unbound(unification.fresh(count)), subs, types)
      }
      let cache = cache_update(cache, ref, required, t)
      #(t, subs, cache)
    }
  }
}
