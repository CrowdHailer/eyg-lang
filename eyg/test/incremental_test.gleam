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
import eyg/incremental/inference

pub fn two_test() {
  // todo("moo")

  let tree =
    e.Let(
      "x",
      e.Integer(1),
      e.Let("y", e.Binary("hey"), e.Lambda("p", e.Variable("y"))),
    )

  let #(root, refs) = source.from_tree(tree)
  io.debug(root)
  io.debug(refs)
  let f = inference.free(refs, [])
  io.debug(list.map(f, set.to_list))
  io.debug(list.at(refs, root))

  // binary
  let path = [1, 0]
  let cursor = cursor.at(path, root, refs)
  io.debug(cursor)
  let [point, ..] = cursor.0
  io.debug(list.at(refs, point))

  let count = javascript.make_reference(0)
  let #(t, subs, cache) =
    inference.cached(root, refs, f, map.new(), env.empty(), sub.none(), count)
  io.debug(t)
  let #(root, refs) = cursor.replace(e.Integer(3), cursor, refs)

  io.debug(refs)
  let f2 = inference.free(refs, f)
  io.debug(list.map(f2, set.to_list))

  let path = [1, 1, 0]
  let cursor = cursor.at(path, root, refs)
  io.debug(cursor)
  let [point, ..] = cursor.0
  io.debug(list.at(refs, point))

  io.debug("====")
  io.debug(cache)
  io.debug("====")

  let #(t2, subs, cache) =
    inference.cached(root, refs, f2, cache, env.empty(), subs, count)
  io.debug(t2)
}

// TODO printing map in node
// TODO binary-size in JS match

pub fn all_test() {
  todo
}
