import gleam/dynamic/decode
import gleam/json
import hub/db/utils
import multiformats/cid/v1
import pog
import untethered/ledger/schema

pub fn insert_entry(cid, entity) -> pog.Query(schema.ArchivedEntry) {
  let cid = v1.to_string(cid)
  "INSERT INTO signatory_entries (cid, payload) VALUES ($1, $2)
  RETURNING id, cid, payload, recorded_at, entity, seq, previous, type_"
  |> pog.query
  |> pog.parameter(pog.text(cid))
  |> pog.parameter(pog.text(json.to_string(entity)))
  |> pog.returning(entry_decoder())
}

// TODO data test 
pub fn list_entries(parameters) -> pog.Query(schema.ArchivedEntry) {
  "SELECT id, cid, payload, recorded_at, entity, seq, previous, type_ FROM signatory_entries ORDER BY id ASC"
  |> pog.query
  // |> pog.parameter(pog.text(entity))
  |> pog.returning(entry_decoder())
}

pub fn list_entries_from_entry(entry_id) {
  "SELECT id, cid, payload, recorded_at, entity, seq, previous, type_
FROM signatory_entries
WHERE entity = (
    SELECT entity
    FROM signatory_entries
    WHERE cid = $1
)
ORDER BY seq ASC;"
  |> pog.query
  |> pog.parameter(pog.text(entry_id))
  |> pog.returning(entry_decoder())
}

fn entry_decoder() {
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
