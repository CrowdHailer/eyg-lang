//// A box is stored as its events, each one records a new file system root.
//// A box has an id and, if it is shared, a name. A box without a name is transient.

import eyg/ir/dag_json
import gleam/dynamic/decode
import gleam/option.{type Option}
import multiformats/cid/v1
import pog

/// The state of a box after the event with this sequence.
pub type Box {
  Box(id: String, name: Option(String), sequence: Int, root: v1.Cid)
}

fn decoder() -> decode.Decoder(Box) {
  use id <- decode.field(0, decode.string)
  use name <- decode.field(1, decode.optional(decode.string))
  use sequence <- decode.field(2, decode.int)
  use root <- decode.field(3, decode.string)
  case v1.from_string(root) {
    Ok(#(root, _)) -> decode.success(Box(id:, name:, sequence:, root:))
    Error(_) ->
      decode.failure(
        Box(id:, name:, sequence:, root: dag_json.vacant_cid),
        "CID",
      )
  }
}

/// A new box starting at `root`, returns no rows when the name is taken.
pub fn create(name: Option(String), root: v1.Cid) -> pog.Query(Box) {
  "WITH box AS (
    INSERT INTO boxes (name) VALUES ($1) ON CONFLICT DO NOTHING RETURNING id, name
  )
  INSERT INTO box_events (box, seq, root)
  SELECT id, 1, $2 FROM box
  RETURNING box, $1::TEXT, seq, root"
  |> pog.query()
  |> pog.parameter(pog.nullable(pog.text, name))
  |> pog.parameter(pog.text(v1.to_string(root)))
  |> pog.returning(decoder())
}

/// A box that was kept in memory, its events are recorded after it.
pub fn insert(id: String, name: Option(String)) -> pog.Query(Nil) {
  "INSERT INTO boxes (id, name) VALUES ($1, $2)"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.parameter(pog.nullable(pog.text, name))
}

/// Returns no rows when the sequence has already been recorded for the box.
/// `change` identifies the change that was merged, if it has an identifier.
pub fn record(box: Box, change: Option(String)) -> pog.Query(Box) {
  "INSERT INTO box_events (box, seq, root, change)
  VALUES ($1, $2, $3, $4)
  ON CONFLICT DO NOTHING
  RETURNING box, $5::TEXT, seq, root"
  |> pog.query()
  |> pog.parameter(pog.text(box.id))
  |> pog.parameter(pog.int(box.sequence))
  |> pog.parameter(pog.text(v1.to_string(box.root)))
  |> pog.parameter(pog.nullable(pog.text, change))
  |> pog.parameter(pog.nullable(pog.text, box.name))
  |> pog.returning(decoder())
}

/// The event that merged a change, if it has been merged.
pub fn merged(id: String, change: String) -> pog.Query(Box) {
  "SELECT e.box, b.name, e.seq, e.root
  FROM box_events e JOIN boxes b ON b.id = e.box
  WHERE e.box = $1 AND e.change = $2"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.parameter(pog.text(change))
  |> pog.returning(decoder())
}

pub fn latest(id: String) -> pog.Query(Box) {
  "SELECT e.box, b.name, e.seq, e.root
  FROM box_events e JOIN boxes b ON b.id = e.box
  WHERE e.box = $1
  ORDER BY e.seq DESC
  LIMIT 1"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning(decoder())
}

/// The latest state of every named box, in order of name.
pub fn named() -> pog.Query(Box) {
  "SELECT DISTINCT ON (b.name) e.box, b.name, e.seq, e.root
  FROM boxes b JOIN box_events e ON e.box = b.id
  WHERE b.name IS NOT NULL
  ORDER BY b.name, e.seq DESC"
  |> pog.query()
  |> pog.returning(decoder())
}
