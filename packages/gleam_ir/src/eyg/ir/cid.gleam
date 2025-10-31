import dag_json as codec
import eyg/ir/dag_json
import eyg/ir/promise
import multiformats/cid/v1
import multiformats/hashes/sha256
import multiformats/hashes/sha256_browser

pub fn from_tree(source) {
  let bytes = dag_json.to_block(source)
  from_block(bytes)
}

pub fn from_block(bytes) {
  let multihash = sha256.digest(bytes)

  v1.Cid(codec.code(), multihash)
  |> v1.to_string
}

pub fn from_tree_async(source) {
  let bytes = dag_json.to_block(source)
  from_block_async(bytes)
}

pub fn from_block_async(bytes) {
  let multihash = sha256_browser.digest(bytes)
  use multihash <- promise.map(multihash)

  v1.Cid(codec.code(), multihash)
  |> v1.to_string
}
