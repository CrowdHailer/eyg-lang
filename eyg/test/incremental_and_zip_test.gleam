import gleam/io
import gleam/list
import gleam/map.{Map}
import gleam/option
import gleam/set.{Set}
import gleam/setx
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/analysis/substitutions as sub
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/env
import eyg/analysis/unification

pub type Exp {
  Var(String)
  Fn(String, Int)
  Let(String, Int, Int)
  Call(Int, Int)
  Integer(Int)
  String(String)
}

fn do_tree_to_ref(
  tree,
  acc,
) -> #(Exp, set.Set(String), List(#(Exp, set.Set(String)))) {
  case tree {
    e.Variable(label) -> {
      let free = setx.singleton(label)
      #(Var(label), free, acc)
    }
    e.Lambda(label, body) -> {
      let #(node, free, acc) = do_tree_to_ref(body, acc)
      let index = list.length(acc)
      let acc = [#(node, free), ..acc]
      let free = set.delete(free, label)
      #(Fn(label, index), free, acc)
    }
    e.Let(label, value, then) -> {
      let #(then, free_t, acc) = do_tree_to_ref(then, acc)
      let then_index = list.length(acc)
      let acc = [#(then, free_t), ..acc]
      let #(value, free_v, acc) = do_tree_to_ref(value, acc)
      let value_index = list.length(acc)
      let acc = [#(value, free_v), ..acc]

      let free = set.union(free_v, set.delete(free_t, label))
      #(Let(label, value_index, then_index), free, acc)
    }
    e.Binary(value) -> #(String(value), set.new(), acc)
    e.Integer(value) -> #(Integer(value), set.new(), acc)
    _ -> todo("rest of ref")
  }
}

fn tree_to_ref(tree) {
  let #(exp, free, acc) = do_tree_to_ref(tree, [])
  let index = list.length(acc)
  let source = list.reverse([#(exp, free), ..acc])
  #(index, source)
}

fn zip_match(node, path_element) {
  case node, path_element {
    Let(_, index, _), 0 -> index
    Let(_, _, index), 1 -> index
    Fn(_, index), 0 -> index
  }
}

fn do_zip(path, refs, current, zoom, root) {
  case path {
    [] -> #([current, ..zoom], root)
    [path_element, ..path] -> {
      let assert Ok(#(node, _free)) = list.at(refs, current)
      let zoom = [current, ..zoom]
      let current = zip_match(node, path_element)
      do_zip(path, refs, current, zoom, root)
    }
  }
}

// root and refs together from tree
fn zip(path, root, refs) {
  case path {
    [] -> #([], root)
    [path_element, ..path] -> {
      let assert Ok(#(node, _free)) = list.at(refs, root)
      let current = zip_match(node, path_element)
      do_zip(path, refs, current, [], root)
    }
  }
}

pub fn do_unzip(old, new, zoom, rev) {
  case zoom {
    [] -> #(new, list.reverse(rev))
    [next, ..zoom] -> {
      let assert Ok(#(node, free)) = list.at(list.reverse(rev), next)
      // TODO free, maybe free should be a separate step
      io.debug(#(node, old))
      let exp = case node {
        Let(label, value, then) if value == old -> Let(label, new, then)
        Let(label, value, then) if then == old -> Let(label, value, new)
        Fn(param, body) if body == old -> Fn(param, new)
        Call(func, arg) if func == old -> Call(new, arg)
        Call(func, arg) if arg == old -> Call(func, new)
        _ -> todo("Can't have a path into literal")
      }
      // TODO real free
      let new = list.length(rev)
      let rev = [#(exp, free), ..rev]
      do_unzip(next, new, zoom, rev)
    }
  }
}

pub fn unzip(tree, cursor, refs) {
  let #(exp, free, acc) = do_tree_to_ref(tree, list.reverse(refs))
  let new = list.length(acc)
  let rev = [#(exp, free), ..acc]
  case cursor {
    #([], old) -> do_unzip(old, new, [], rev)
    #([old, ..zoom], root) -> do_unzip(old, new, list.append(zoom, [root]), rev)
  }
}

// fn do_w(env, exp, refs, cache) {
//   let t = todo
//   let #(s, t, cache) = case node {
//     Let(label, v, t) -> {
//       let #(s1, t1, cache) = w(env, v, refs, cache)
//       let env1 = map.insert(env, label, t1)
//       let #(s2, t2, cache) = w(env1, t, refs, cache)
//       // TODO real s
//       #(s2, t2, cache)
//     }
//     Var(x) -> {
//       let assert Ok(t) = map.get(env, x)
//       #(sub.none(), t, cache)
//     }
//     Integer(_) -> #(sub.none(), t.Integer, cache)

//     _ -> todo("22w")
//   }
// }

// // Need single map of substitutions, is this the efficient J algo?
// // Free should be easy in bottom up order assume need value is already present
// // probably not fast in edits to std lib. maybe with only part of record field it would be faster.
// // but if async and cooperative then we can just manage without as needed.
// // TODO have building type stuff happen at startup. try it out in browser
// fn w(env, exp, refs, cache) {
//   let assert Ok(#(node, free)) = list.at(refs, exp)
//   // can always use small env
//   let env = map.take(env, set.to_list(free))
//   case map.get(cache, exp) {
//     Ok(envs) ->
//       case map.get(envs, env) {
//         Ok(r) -> r
//         _ -> do_w(env, exp, refs, cache)
//       }
//     _ -> do_w(env, exp, refs, cache)
//   }
//   let t = todo
//   let cache =
//     map.update(
//       cache,
//       exp,
//       fn(previous) {
//         let by_env = option.unwrap(previous, map.new())
//         map.insert(by_env, map.take(env, set.to_list(free)), t)
//       },
//     )
//   #(s, t, cache)
// }

pub fn w(env, exp, refs, cache) -> Nil {
  todo
}

pub fn two_test() {
  let tree =
    e.Let(
      "x",
      e.Integer(1),
      e.Let("y", e.Binary("hey"), e.Lambda("p", e.Variable("y"))),
    )

  let #(root, refs) = tree_to_ref(tree)
  io.debug(root)
  io.debug(refs)
  io.debug(list.at(refs, root))

  // binary
  let path = [1, 0]
  let cursor = zip(path, root, refs)
  io.debug(cursor)
  let [point, ..] = cursor.0
  io.debug(list.at(refs, point))

  w(map.new(), root, refs, map.new())
  unzip(e.Integer(10), cursor, refs)
  |> io.debug

  todo("moo")
  let path = [1, 1, 0]
  let cursor = zip(path, root, refs)
  io.debug(cursor)
  let [point, ..] = cursor.0
  io.debug(list.at(refs, point))
}
// TODO printing map in node
// TODO binary-size in JS match
