import dag_json as codec
import eyg/ir/dag_json
import gleam/javascript/promise
import multiformats/cid
import multiformats/hashes/sha256_browser as sha256

pub fn from_tree(source) {
  let bytes = dag_json.to_block(source)
  from_block(bytes)
}

pub fn from_block(bytes) {
  let multihash = sha256.digest(bytes)
  use multihash <- promise.map(multihash)

  cid.create_v1(codec.code(), multihash)
  |> cid.to_string
}
