import eyg/ir/cid
import eyg/ir/tree
import gleam/crypto
import multiformats/cid/v1

pub fn from_tree(source: #(tree.Expression(a), a)) -> v1.Cid {
  let cid.Sha256(bytes:, resume:) = cid.from_tree(source)
  resume(crypto.hash(crypto.Sha256, bytes))
}
