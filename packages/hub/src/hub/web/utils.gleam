import dag_json
import eyg/ir/cid
import gleam/crypto
import gleam/json
import gleam/string
import multiformats/cid/v1
import multiformats/hashes
import wisp

pub fn do_decode(data, decoder, then) {
  case json.parse(data, decoder) {
    Ok(value) -> then(value)
    Error(reason) -> wisp.bad_request(string.inspect(reason))
  }
}

pub fn cid_from_tree(source) {
  let cid.Sha256(bytes:, resume:) = cid.from_tree(source)
  resume(crypto.hash(crypto.Sha256, bytes))
}

pub fn cid_from_block(bytes) {
  v1.Cid(
    dag_json.code(),
    hashes.Multihash(hashes.Sha256, crypto.hash(crypto.Sha256, bytes)),
  )
}
