import eyg/ir/dag_json
import gleam/dynamic/decode
import gleam/json
import multiformats/cid/v1
import untethered/ledger/schema

pub fn cid_decoder() {
  use encoded <- decode.then(decode.string)
  case v1.from_string(encoded) {
    Ok(#(cid, _)) -> decode.success(cid)
    Error(_) -> decode.failure(dag_json.vacant_cid, "CID")
  }
}

pub type ArchivedEntry =
  schema.ArchivedEntry

pub type PullParameters =
  schema.PullParameters

pub type PullResponse =
  schema.PullResponse

pub const archived_entry_decoder = schema.archived_entry_decoder

pub const pull_response_decoder = schema.pull_response_decoder

pub type ShareResponse =
  v1.Cid

pub fn share_response_decoder() -> decode.Decoder(ShareResponse) {
  use cid <- decode.field("cid", cid_decoder())
  decode.success(cid)
}

pub fn share_response_encode(cid: ShareResponse) {
  json.object([#("cid", json.string(v1.to_string(cid)))])
}

pub fn failure_decoder() {
  use reason <- decode.field("reason", decode.string)
  decode.success(reason)
}
