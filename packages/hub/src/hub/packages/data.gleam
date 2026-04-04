import eyg/hub/publisher
import gleam/dynamic/decode
import gleam/json
import hub/cid
import hub/db/utils
import multiformats/cid/v1
import pog
import untethered/ledger/schema

pub fn insert_release(entry: publisher.Entry) {
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

fn archived_entry_decoder() {
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

pub fn list_events(
  db: pog.Connection,
  parameters: schema.PullParameters,
) -> Result(List(schema.ArchivedEntry), pog.QueryError) {
  todo
}
