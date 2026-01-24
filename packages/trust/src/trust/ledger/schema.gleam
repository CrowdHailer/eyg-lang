import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}

pub type Archived {
  Archived(cursor: Int, entity: String, sequence: Int, entry: String)
}

pub fn archived_encode(archived) {
  let Archived(cursor:, entity:, sequence:, entry:) = archived
  json.object([
    #("cursor", json.int(cursor)),
    #("entity", json.string(entity)),
    #("sequence", json.int(sequence)),
    #("entry", json.string(entry)),
  ])
}

pub fn archived_decoder() {
  use cursor <- decode.field("cursor", decode.int)
  use entity <- decode.field("entity", decode.string)
  use sequence <- decode.field("sequence", decode.int)
  use entry <- decode.field("entry", decode.string)
  decode.success(Archived(cursor:, entity:, sequence:, entry:))
}

pub type EntriesResponse(sig, t) {
  EntriesResponse(entries: List(Entry))
}

pub fn entries_response_decoder() {
  use entries <- decode.field("entries", decode.list(entry_decoder()))
  // use cursor <- decode.field("cursor", decode.int)
  decode.success(EntriesResponse(entries:))
}

pub fn entries_response_encode(entries) {
  json.object([
    #("entries", json.array(entries, entry_encode)),
  ])
}

/// A ledger entry is the full record indexed in a ledger,
/// including the entity and sequence
pub type Entry {
  Entry(
    cursor: Int,
    cid: String,
    payload: String,
    entity: String,
    sequence: Int,
    previous: Option(String),
    type_: String,
  )
}

fn entry_decoder() {
  use cursor <- decode.field("cursor", decode.int)
  use cid <- decode.field("cid", decode.string)
  use payload <- decode.field("payload", decode.string)
  use entity <- decode.field("entity", decode.string)
  use sequence <- decode.field("sequence", decode.int)
  use previous <- decode.optional_field(
    "previous",
    None,
    decode.map(decode.string, Some),
  )
  use type_ <- decode.field("type", decode.string)
  decode.success(Entry(
    cursor:,
    cid:,
    payload:,
    entity:,
    sequence:,
    previous:,
    type_:,
  ))
}

fn entry_encode(entry) {
  let Entry(cursor:, cid:, payload:, entity:, sequence:, previous:, type_:) =
    entry
  json.object([
    #("cursor", json.int(cursor)),
    #("cid", json.string(cid)),
    #("payload", json.string(payload)),
    #("entity", json.string(entity)),
    #("sequence", json.int(sequence)),
    #("type", json.string(type_)),
    ..case previous {
      Some(previous) -> [#("previous", json.string(previous))]
      None -> []
    }
  ])
}
