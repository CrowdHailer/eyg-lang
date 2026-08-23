import eyg/ir/cid
import eyg/ir/tree as ir
import gleam/crypto
import midas/continuation
import multiformats/cid/v1

fn hash_sha256(bytes) {
  continuation.return(crypto.hash(crypto.Sha256, bytes))
}

pub fn from_block(bytes: BitArray) -> v1.Cid {
  cid.from_block(bytes, hash_sha256)(fn(x) { x })
}

pub fn from_tree(source: ir.Node(_)) -> v1.Cid {
  cid.from_tree(source, hash_sha256)(fn(x) { x })
}
