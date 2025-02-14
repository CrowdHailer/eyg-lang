import dag_json as codec
import eyg/ir/dag_json
import multiformats/cid
import multiformats/hashes/sha256

pub fn from_tree(source) {
  let bytes = dag_json.to_block(source)
  let multihash = sha256.digest(bytes)
  cid.create_v1(codec.code(), multihash)
  |> cid.to_string
}
