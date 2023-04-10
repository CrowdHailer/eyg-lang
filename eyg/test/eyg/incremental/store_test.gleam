import gleam/io
import gleam/map
import gleam/set
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/incremental/source
import eyg/incremental/store
import gleeunit/should

// TODO printing map in node
// TODO binary-size in JS match

pub fn literal_test() {
  let s = store.empty()

  let tree = e.Binary("hello")
  let #(ref_binary, s) = store.load(s, tree)
  should.equal(ref_binary, 0)
  //   should.equal(store.tree(s, ref_binary), Ok(tree))
  let assert Ok(#(free, s)) = store.free(s, ref_binary)
  should.equal(map.size(s.free), 1)
  should.equal(free, set.new())
  let assert Ok(#(t, s)) = store.type_(s, ref_binary)
  should.equal(map.size(s.types), 1)
  should.equal(t, t.Binary)

  let #(ref_integer, s) = store.load(s, e.Integer(5))
  should.equal(ref_integer, 1)
  let assert Ok(#(free, s)) = store.free(s, ref_integer)
  should.equal(map.size(s.free), 2)
  should.equal(free, set.new())
  let assert Ok(#(t, s)) = store.type_(s, ref_integer)
  should.equal(map.size(s.types), 2)
  should.equal(t, t.Integer)
}

pub fn function_unification_test() {
  let s = store.empty()

  let tree = e.Apply(e.Lambda("x", e.Variable("x")), e.Binary("hey"))
  let #(root, s) = store.load(s, tree)
  should.equal(root, 3)
  should.equal(map.size(s.source), 4)

  let assert Ok(#(t, s)) = store.type_(s, root)
  should.equal(t, t.Binary)
  should.equal(map.size(s.free), 4)
  should.equal(map.size(s.types), 4)

  let assert Ok(c) = store.cursor(s, root, [1])
  let assert Ok(node) = store.focus(s, c)
  should.equal(node, source.String("hey"))
  let assert Ok(#(root1, s)) = store.replace(s, c, source.Integer(10))
  should.equal(map.size(s.source), 6)

  let assert Ok(c) = store.cursor(s, root, [0, 0])
  let assert Ok(node) = store.focus(s, c)
  should.equal(node, source.Var("x"))
  let assert Ok(#(root2, s)) = store.replace(s, c, source.Empty)
  should.equal(map.size(s.source), 9)
  // source increase by path length + 1
  // free and types are lazy so stay at 4
  should.equal(map.size(s.free), 4)
  should.equal(map.size(s.types), 4)

  let assert Ok(#(t, s)) = store.type_(s, root1)
  should.equal(t, t.Integer)
  let assert Ok(#(t, s)) = store.type_(s, root2)
  should.equal(t, t.unit)

  should.equal(map.size(s.free), 9)
  should.equal(map.size(s.types), 9)
}

pub fn let_literal_test() {
  let s = store.empty()

  let tree = e.Let("x", e.Binary("hey"), e.Variable("x"))
  let #(root, s) = store.load(s, tree)
  should.equal(root, 2)
  should.equal(map.size(s.source), 3)

  let assert Ok(#(t, s)) = store.type_(s, root)
  should.equal(t, t.Binary)
  should.equal(map.size(s.free), 3)
  should.equal(map.size(s.types), 3)
  io.debug(#(
    "============",
    store.ref_group(s)
    |> map.to_list,
  ))

  let assert Ok(c) = store.cursor(s, root, [0])
  let assert Ok(node) = store.focus(s, c)
  should.equal(node, source.String("hey"))
  let assert Ok(#(root1, s)) = store.replace(s, c, source.Integer(10))
  should.equal(map.size(s.source), 5)

  let assert Ok(c) = store.cursor(s, root, [1])
  let assert Ok(node) = store.focus(s, c)
  should.equal(node, source.Var("x"))
  let assert Ok(#(root2, s)) = store.replace(s, c, source.Empty)
  should.equal(map.size(s.source), 7)
  // source increase by path length + 1
  // free and types are lazy so stay at 4
  should.equal(map.size(s.free), 3)
  should.equal(map.size(s.types), 3)

  let assert Ok(#(t, s)) = store.type_(s, root1)
  should.equal(t, t.Integer)
  let assert Ok(#(t, s)) = store.type_(s, root2)
  should.equal(t, t.unit)

  should.equal(map.size(s.free), 7)
  should.equal(map.size(s.types), 7)
  io.debug(#(
    "============",
    store.ref_group(s)
    |> map.to_list,
  ))
}

pub fn fn_poly_test() {
  let s = store.empty()

  let tree =
    e.Let(
      "id",
      e.Lambda("x", e.Variable("x")),
      e.Apply(e.Variable("id"), e.Integer(10)),
    )
  let #(root, s) = store.load(s, tree)
  should.equal(root, 5)
  should.equal(map.size(s.source), 6)

  let assert Ok(#(t, s)) = store.type_(s, root)
  should.equal(t, t.Integer)
  should.equal(map.size(s.free), 6)
  should.equal(map.size(s.types), 6)
}

pub fn nested_fn_test() {
  let s = store.empty()

  let tree = e.Lambda("x", e.Lambda("y", e.Empty))
  let #(root, s) = store.load(s, tree)
  should.equal(root, 2)
  should.equal(map.size(s.source), 3)

  let assert Ok(#(t, s)) = store.type_(s, root)
  should.equal(
    t,
    t.Fun(
      t.Unbound(0),
      t.Closed,
      t.Fun(t.Unbound(1), t.Closed, t.Record(t.Closed)),
    ),
  )
  should.equal(map.size(s.free), 3)
  should.equal(map.size(s.types), 3)

  let assert Ok(c) = store.cursor(s, root, [0, 0])
  let assert Ok(node) = store.focus(s, c)
  should.equal(node, source.Empty)
  let assert Ok(#(root1, s)) = store.replace(s, c, source.Integer(10))
  should.equal(map.size(s.source), 6)

  let assert Ok(node) = store.focus(s, c)
  // same cursor points to same item, store replace gives new root
  should.equal(node, source.Empty)
  let assert Ok(#(root2, s)) = store.replace(s, c, source.Var("y"))
  should.equal(map.size(s.source), 9)
  // source increase by path length + 1
  // free and types are lazy so stay at 4
  should.equal(map.size(s.free), 3)
  should.equal(map.size(s.types), 3)

  let assert Ok(#(t, s)) = store.type_(s, root1)
  should.equal(
    t,
    t.Fun(t.Unbound(2), t.Closed, t.Fun(t.Unbound(3), t.Closed, t.Integer)),
  )
  let assert Ok(#(t, s)) = store.type_(s, root2)
  should.equal(
    t,
    t.Fun(t.Unbound(4), t.Closed, t.Fun(t.Unbound(5), t.Closed, t.Unbound(5))),
  )

  should.equal(map.size(s.free), 9)
  should.equal(map.size(s.types), 9)
}

pub fn branched_apply_test() {
  let s = store.empty()

  let tree =
    e.Let(
      "id",
      e.Lambda("x", e.Variable("x")),
      e.Apply(
        e.Apply(e.Variable("id"), e.Variable("id")),
        e.Apply(e.Variable("id"), e.Integer(1)),
      ),
    )

  let #(root, s) = store.load(s, tree)
  should.equal(root, 9)
  should.equal(map.size(s.source), 10)

  let assert Ok(c) = store.cursor(s, root, [])
  let assert Ok(node) = store.focus(s, c)
  should.equal(node, source.Let("id", 8, 6))
  let assert Ok(#(vars, s)) = store.free(s, root)
  should.equal(vars, set.new())
  should.equal(map.size(s.free), 10)
  should.equal(map.size(s.types), 0)

  let assert Ok(#(t, s)) = store.type_(s, root)
  should.equal(map.size(s.types), 10)
  io.debug(
    s.substitutions.terms
    |> map.to_list,
  )
  io.debug(#(
    "============",
    store.ref_group(s)
    |> map.to_list,
  ))
  should.equal(t, t.Integer)
  panic
}





