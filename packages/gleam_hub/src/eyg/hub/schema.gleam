import eyg/ir/dag_json
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/option
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

pub fn package_entry(
  cursor cursor: Int,
  cid cid: v1.Cid,
  payload payload: String,
  entity entity: v1.Cid,
  sequence sequence: Int,
  previous previous: option.Option(v1.Cid),
  type_ type_: String,
) -> ArchivedEntry {
  schema.ArchivedEntry(
    cursor:,
    cid:,
    payload:,
    entity:,
    sequence:,
    previous:,
    type_:,
  )
}

pub type PullParameters =
  schema.PullParameters

pub type PullResponse =
  schema.PullResponse

pub const archived_entry_decoder = schema.archived_entry_decoder

pub const pull_response_decoder = schema.pull_response_decoder

pub const entries_response_encode = schema.entries_response_encode

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

/// A file of an artifact bundle.
pub type ArtifactFile {
  ArtifactFile(path: String, media_type: String, content: BitArray)
}

pub fn artifact_encode(name: String, files: List(ArtifactFile)) {
  json.object([#("name", json.string(name)), #("files", files_encode(files))])
}

pub fn artifact_decoder() -> decode.Decoder(#(String, List(ArtifactFile))) {
  use name <- decode.field("name", decode.string)
  use files <- decode.field("files", decode.list(file_decoder()))
  decode.success(#(name, files))
}

fn files_encode(files) {
  json.array(files, fn(file) {
    let ArtifactFile(path:, media_type:, content:) = file
    json.object([
      #("path", json.string(path)),
      #("media_type", json.string(media_type)),
      #("content", json.string(bit_array.base64_encode(content, True))),
    ])
  })
}

fn file_decoder() {
  use path <- decode.field("path", decode.string)
  use media_type <- decode.field("media_type", decode.string)
  use content <- decode.field("content", base64_decoder())
  decode.success(ArtifactFile(path:, media_type:, content:))
}

fn base64_decoder() {
  use encoded <- decode.then(decode.string)
  case bit_array.base64_decode(encoded) {
    Ok(content) -> decode.success(content)
    Error(Nil) -> decode.failure(<<>>, "base64")
  }
}

/// A shared artifact. Only whoever shared it gets the secret,
/// sharing a newer version with the secret points the artifact to it.
pub type SharedArtifact {
  SharedArtifact(id: String, secret: String)
}

pub fn shared_artifact_encode(shared: SharedArtifact) {
  let SharedArtifact(id:, secret:) = shared
  json.object([#("id", json.string(id)), #("secret", json.string(secret))])
}

pub fn shared_artifact_decoder() -> decode.Decoder(SharedArtifact) {
  use id <- decode.field("id", decode.string)
  use secret <- decode.field("secret", decode.string)
  decode.success(SharedArtifact(id:, secret:))
}

/// A request to share an artifact, as a newer version of `previous` if given.
pub fn share_artifact_encode(
  name: String,
  files: List(ArtifactFile),
  previous: option.Option(SharedArtifact),
) -> json.Json {
  let previous = case previous {
    option.Some(previous) -> [#("previous", shared_artifact_encode(previous))]
    option.None -> []
  }
  json.object([
    #("name", json.string(name)),
    #("files", files_encode(files)),
    ..previous
  ])
}

pub fn share_artifact_decoder() -> decode.Decoder(
  #(String, List(ArtifactFile), option.Option(SharedArtifact)),
) {
  use #(name, files) <- decode.then(artifact_decoder())
  use previous <- decode.optional_field(
    "previous",
    option.None,
    decode.map(shared_artifact_decoder(), option.Some),
  )
  decode.success(#(name, files, previous))
}
