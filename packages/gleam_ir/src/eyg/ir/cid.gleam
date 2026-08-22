import dag_json
import eyg/ir/dag_json as djson
import eyg/ir/tree as ir
import midas/continuation.{type Continuation as K}
import multiformats/cid/v1
import multiformats/hashes

pub fn from_tree(
  source: ir.Node(a),
  hash_sha256: fn(BitArray) -> K(t, BitArray),
) -> K(t, v1.Cid) {
  let bytes = djson.to_block(source)
  from_block(bytes, hash_sha256)
}

pub fn from_block(
  bytes: BitArray,
  hash_sha256: fn(BitArray) -> K(t, BitArray),
) -> K(t, v1.Cid) {
  use digest <- continuation.then(hash_sha256(bytes))
  let multihash = hashes.Multihash(hashes.Sha256, digest)
  continuation.return(v1.Cid(dag_json.code(), multihash))
}
