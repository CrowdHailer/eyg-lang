import gleam/io
import gleam/map
import gleam/set
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/incremental/source
import eyg/incremental/store
import eyg/incremental/cursor
import gleeunit/should

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
  should.equal(map.size(s.free), 4)
  should.equal(map.size(s.types), 4)

  let assert Ok(c) = store.cursor(s, root, [1])
  let assert Ok(node) = store.focus(s, c)
  should.equal(node, source.String("hey"))

  // s does not change on fetching inner type
  let assert Ok(#(type_, _)) = store.type_(s, cursor.inner(c))
  should.equal(type_, t.Binary)

  let assert Ok(c) = store.cursor(s, root, [0, 0])
  let assert Ok(node) = store.focus(s, c)
  should.equal(node, source.Var("x"))

  // io.debug(node) test node

  // s should not change
  let assert Ok(#(type_, _)) = store.type_(s, cursor.inner(c))
  // binary -> binary because not generalised in let statement
  should.equal(type_, t.Fun(t.Binary, t.Closed, t.Binary))

  // should.equal(n, )
  should.equal(t, t.Binary)
}
// pub fn let_scope_test() {
//   let s = store.empty()

//   let tree =
//     e.Let(
//       "x",
//       e.Integer(10),
//       e.Let(
//         "y",
//         e.Integer(20),
//         e.Apply(
//           e.Apply(e.Cons, e.Variable("y")),
//           e.Apply(e.Apply(e.Cons, e.Variable("x")), e.Tail),
//         ),
//       ),
//     )
//   let #(ref_binary, s) = store.load(s, tree)
//   should.equal(ref_binary, 12)
//   should.equal(map.size(s.source), 13)

//   let assert Ok(#(free, s)) = store.free(s, ref_binary)
//   should.equal(map.size(s.free), 13)
//   should.equal(free, set.new())
//   let assert Ok(#(t, s)) = store.type_(s, ref_binary)
//   should.equal(map.size(s.types), 13)
//   should.equal(t, t.LinkedList(t.Integer))
// }
