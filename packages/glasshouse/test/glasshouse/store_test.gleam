import eyg/ir/tree as ir
import glasshouse/helpers.{sha256}
import glasshouse/store

pub fn put_is_content_addressed_test() {
  let #(store, a) = store.put_binary(store.new(), <<"hello">>, sha256)
  let #(store, b) = store.put_binary(store, <<"hello">>, sha256)
  assert a == b
  assert store.get_binary(store, a) == Ok(<<"hello">>)
}

pub fn different_content_different_cid_test() {
  let #(_, a) = store.put_binary(store.new(), <<"a">>, sha256)
  let #(_, b) = store.put_binary(store.new(), <<"b">>, sha256)
  assert a != b
}

pub fn get_node_round_trip_test() {
  let node = #(ir.Apply(#(ir.Tag("Ok"), Nil), #(ir.Integer(5), Nil)), Nil)
  let #(store, id) = store.put_node(store.new(), node, sha256)
  assert store.get_node(store, id) == Ok(node)
}

pub fn missing_module_test() {
  assert store.get_node(store.new(), "bafy")
    == Error("missing module in store bafy")
}

pub fn get_binary_rejects_other_modules_test() {
  let #(store, id) = store.put_node(store.new(), #(ir.Integer(1), Nil), sha256)
  let assert Error(_) = store.get_binary(store, id)
}

pub fn corrupt_finds_tampered_blocks_test() {
  let #(store, id) = store.put_binary(store.new(), <<"x">>, sha256)
  assert store.corrupt(store, sha256) == []
  let store = store.merge(store, store.from_list([#(id, <<"{}">>)]))
  assert store.corrupt(store, sha256) == [id]
}
