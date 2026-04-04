import eyg/hub/publisher
import gleam/dynamic/decode
import gleam/json
import hub/cid
import hub/db/utils
import multiformats/cid/v1
import pog
import untethered/ledger/schema

pub fn insert_release(entry: publisher.Entry) -> pog.Query(schema.ArchivedEntry) {
  let data = publisher.encode(entry)
  let json = json.to_string(data)
  let cid = cid.from_block(<<json:utf8>>)
  let cid = v1.to_string(cid)
  "INSERT INTO package_entries (cid, payload)
VALUES ($1, $2) 
RETURNING id, cid, payload, recorded_at, entity, seq, previous, type_"
  |> pog.query()
  |> pog.parameter(pog.text(cid))
  |> pog.parameter(pog.text(json))
  |> pog.returning(archived_entry_decoder())
}

fn archived_entry_decoder() -> decode.Decoder(schema.ArchivedEntry) {
  use cursor <- decode.field(0, decode.int)
  use cid <- decode.field(1, utils.cid_decoder())
  use payload <- decode.field(2, decode.string)
  // use recorded_at <- decode.field(3, decode.int)
  use entity <- decode.field(4, utils.cid_decoder())
  use sequence <- decode.field(5, decode.int)
  use previous <- decode.field(6, decode.optional(utils.cid_decoder()))
  use type_ <- decode.field(7, decode.string)
  decode.success(schema.ArchivedEntry(
    cursor:,
    cid:,
    payload:,
    entity:,
    sequence:,
    previous:,
    type_:,
  ))
}

pub type Package {
  Package(id: String, version: Int, module: String, released_at: utils.DateTime)
}

fn package_decoder() -> decode.Decoder(Package) {
  use id <- decode.field(0, decode.string)
  use version <- decode.field(1, decode.int)
  use module <- decode.field(2, decode.string)
  use released_at <- decode.field(3, utils.datetime_decoder())
  decode.success(Package(id:, version:, module:, released_at:))
}

pub fn list_packages() -> pog.Query(Package) {
  "SELECT package, version_, module, recorded_at
  FROM latest_releases
  ORDER BY recorded_at DESC"
  |> pog.query()
  |> pog.returning(package_decoder())
}

pub type Release {
  Release(
    package: String,
    version: Int,
    module: String,
    released_at: utils.DateTime,
  )
}

fn release_decoder() -> decode.Decoder(Release) {
  use package <- decode.field(0, decode.string)
  use version <- decode.field(1, decode.int)
  use module <- decode.field(2, decode.string)
  use released_at <- decode.field(3, utils.datetime_decoder())

  decode.success(Release(package:, version:, module:, released_at:))
}

pub fn list_releases(entity: String) -> pog.Query(Release) {
  "SELECT package, version_, module, recorded_at
  FROM releases 
  WHERE package = $1
  ORDER BY recorded_at DESC"
  |> pog.query()
  |> pog.parameter(pog.text(entity))
  |> pog.returning(release_decoder())
}

pub fn list_events(
  parameters: schema.PullParameters,
) -> pog.Query(schema.ArchivedEntry) {
  "SELECT id, cid, payload, recorded_at, entity, seq, previous, type_
  FROM registry_events
  WHERE id > $1
  ORDER BY id ASC
  LIMIT $2"
  |> pog.query()
  |> pog.parameter(pog.int(parameters.since))
  |> pog.parameter(pog.int(parameters.limit))
  |> pog.returning(archived_entry_decoder())
}

pub fn list_entries_from_entry(
  entry_id: v1.Cid,
) -> pog.Query(schema.ArchivedEntry) {
  "SELECT id, cid, payload, recorded_at, entity, seq, previous, type_
FROM package_entries
WHERE entity = (
    SELECT entity
    FROM package_entries
    WHERE cid = $1
)
ORDER BY seq ASC;"
  |> pog.query
  |> pog.parameter(pog.text(v1.to_string(entry_id)))
  |> pog.returning(archived_entry_decoder())
}
