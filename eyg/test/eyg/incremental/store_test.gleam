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
  let assert Ok(#(free, s, _)) = store.free(s, ref_binary, [])
  should.equal(map.size(s.free), 1)
  should.equal(free, set.new())
  let assert Ok(#(t, s)) = store.type_(s, ref_binary)
  should.equal(map.size(s.types), 1)
  should.equal(t, t.Binary)

  let #(ref_integer, s) = store.load(s, e.Integer(5))
  should.equal(ref_integer, 1)
  let assert Ok(#(free, s, _)) = store.free(s, ref_integer, [])
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

  panic("not here because type_ doesn't work to just reach in")
  // hash of type or id includes free
  // TODO need type in tree, and errors

  // s does not change on fetching inner type
  let assert Ok(#(type_, _)) = store.type_(s, cursor.inner(c))
  should.equal(type_, t.Binary)

  let assert Ok(c) = store.cursor(s, root, [0, 0])
  let assert Ok(node) = store.focus(s, c)
  should.equal(node, source.Var("x"))

  // s does not change on fetching inner type
  io.debug("------------")
  io.debug(#(
    cursor.inner(c),
    map.keys(s.types),
    s.types
    |> map.get(cursor.inner(c)),
  ))
  // How do I get the actual type value. only root works
  // |> map.to_list,
  let assert Ok(#(type_, _)) = store.type_(s, cursor.inner(c))
  // binary -> binary because not generalised in let statement
  should.equal(type_, t.Fun(t.Binary, t.Closed, t.Binary))
  io.debug("------------")
  // should.equal(n, )
}

pub fn let_test() {
  let s = store.empty()

  let tree =
    e.Let(
      "x",
      e.Let("tmp", e.Binary("i"), e.Binary("o")),
      e.Let(
        "y",
        e.Integer(1),
        e.Apply(e.Apply(e.Extend("a"), e.Variable("x")), e.Empty),
      ),
    )
  let #(root, s) = store.load(s, tree)
  should.equal(root, 10)
  should.equal(map.size(s.source), 11)

  let assert Ok(#(f, s, _)) = store.free(s, root, [])
  should.equal(f, set.new())
  should.equal(map.size(s.free), 11)
  // Where is it going wrong
  should.equal(map.size(s.types), 0)
  // all seems to work.
  // TODO where am I loosing elements
}
// TODO generalization test
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

//   let assert Ok(#(free, s,_)) = store.free(s, ref_binary, [])
//   should.equal(map.size(s.free), 13)
//   should.equal(free, set.new())
//   let assert Ok(#(t, s)) = store.type_(s, ref_binary)
//   should.equal(map.size(s.types), 13)
//   should.equal(t, t.LinkedList(t.Integer))
// }
