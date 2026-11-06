//// An in-memory block store shared by every session.
////
//// Blocks are only ever added and are keyed by their CID,
//// so concurrent writers cannot conflict.
//// The table belongs to the process that creates it and is deleted when
//// that process exits, so create it from a long lived process.

import multiformats/cid/v1.{type Cid}
import unixfs

pub type Store

@external(erlang, "cloud_store_ffi", "new")
pub fn new() -> Store

@external(erlang, "cloud_store_ffi", "insert")
fn insert(store: Store, key: BitArray, block: BitArray) -> Nil

@external(erlang, "cloud_store_ffi", "lookup")
fn lookup(store: Store, key: BitArray) -> Result(BitArray, Nil)

/// Number of blocks held.
@external(erlang, "cloud_store_ffi", "size")
pub fn size(store: Store) -> Int

/// Add a block and return its CID.
pub fn put(store: Store, code: Int, block: BitArray) -> Cid {
  let cid = unixfs.cid(code, block)
  insert(store, v1.to_bytes(cid), block)
  cid
}

pub fn get(store: Store, cid: Cid) -> Result(BitArray, Nil) {
  lookup(store, v1.to_bytes(cid))
}
