import eyg/ir/cid
import gleam/crypto
import multiformats/cid/v1

pub fn cid_from_block(bytes: BitArray) -> v1.Cid {
  let cid.Sha256(bytes, resume) = cid.from_block(bytes)
  let hash = crypto.hash(crypto.Sha256, bytes)
  resume(hash)
}
