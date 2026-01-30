import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// A ledger entry is the full record indexed in a ledger,
/// including the entity and sequence
pub type ArchivedEntry {
  ArchivedEntry(
    cursor: Int,
    cid: String,
    payload: String,
    entity: String,
    sequence: Int,
    previous: Option(String),
    type_: String,
  )
}

pub fn archived_entry_decoder() {
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
  decode.success(ArchivedEntry(
    cursor:,
    cid:,
    payload:,
    entity:,
    sequence:,
    previous:,
    type_:,
  ))
}

pub fn archived_entry_encode(entry) {
  let ArchivedEntry(
    cursor:,
    cid:,
    payload:,
    entity:,
    sequence:,
    previous:,
    type_:,
  ) = entry
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

pub type PullParameters {
  PullParameters(since: Int, limit: Int, entities: List(String))
}

pub fn pull_parameters_from_query(query) {
  let since =
    list.key_find(query, "since")
    |> result.try(int.parse)
    |> result.unwrap(0)

  let limit =
    list.key_find(query, "limit")
    |> result.try(int.parse)
    |> result.unwrap(1000)

  let entities =
    list.key_find(query, "entities")
    |> result.map(string.split(_, ","))
    |> result.unwrap([])
  PullParameters(since:, limit:, entities:)
}

pub fn pull_parameters_to_query(parameters) {
  let PullParameters(since:, limit:, entities:) = parameters
  [
    case since {
      0 -> []
      n -> [#("since", int.to_string(n))]
    },
    case limit {
      1000 -> []
      n -> [#("limit", int.to_string(n))]
    },
    case entities {
      [] -> []
      _ -> [#("entities", string.join(entities, ","))]
    },
  ]
  |> list.flatten()
}

pub type EntriesResponse {
  EntriesResponse(entries: List(ArchivedEntry))
}

pub fn entries_response_decoder() {
  use entries <- decode.field("entries", decode.list(archived_entry_decoder()))
  // use cursor <- decode.field("cursor", decode.int)
  decode.success(EntriesResponse(entries:))
}

pub fn entries_response_encode(entries) {
  json.object([
    #("entries", json.array(entries, archived_entry_encode)),
  ])
}
