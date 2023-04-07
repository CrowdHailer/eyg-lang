import gleam/io
import gleam/map
import gleam/set
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/incremental/store
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
