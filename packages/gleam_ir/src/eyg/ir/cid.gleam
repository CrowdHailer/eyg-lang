import dag_json
import eyg/ir/dag_json as djson
import multiformats/cid/v1
import multiformats/hashes

/// To make the gleam_ir library portable over browser, node and erlang you need to bring your own sha implementation
pub type Effect(t) {
  Sha256(bytes: BitArray, resume: fn(BitArray) -> t)
}

pub fn from_tree(source) {
  let bytes = djson.to_block(source)
  from_block(bytes)
}

pub fn from_block(bytes) {
  Sha256(bytes:, resume: fn(digest) {
    let multihash = hashes.Multihash(hashes.Sha256, digest)
    v1.Cid(dag_json.code(), multihash)
  })
}
