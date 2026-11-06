import cloud/store
import unixfs

pub fn put_then_get_test() {
  let s = store.new()
  let cid = store.put(s, unixfs.raw_code, <<"hello">>)
  assert cid == unixfs.file_cid(<<"hello">>)
  assert store.get(s, cid) == Ok(<<"hello">>)
}

pub fn identical_blocks_are_stored_once_test() {
  let s = store.new()
  let a = store.put(s, unixfs.raw_code, <<"same">>)
  let b = store.put(s, unixfs.raw_code, <<"same">>)
  assert a == b
  assert store.size(s) == 1
}

pub fn missing_block_test() {
  let s = store.new()
  assert store.get(s, unixfs.file_cid(<<"absent">>)) == Error(Nil)
}
