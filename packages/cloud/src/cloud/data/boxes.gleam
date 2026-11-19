//// A box is stored as its events, each one records a new file system root.

import eyg/ir/dag_json
import gleam/dynamic/decode
import multiformats/cid/v1
import pog

/// The state of a box after the event with this sequence.
pub type Box {
  Box(name: String, sequence: Int, root: v1.Cid)
}

fn decoder() -> decode.Decoder(Box) {
  use name <- decode.field(0, decode.string)
  use sequence <- decode.field(1, decode.int)
  use root <- decode.field(2, decode.string)
  case v1.from_string(root) {
    Ok(#(root, _)) -> decode.success(Box(name:, sequence:, root:))
    Error(_) ->
      decode.failure(Box(name:, sequence:, root: dag_json.vacant_cid), "CID")
  }
}

/// Returns no rows when the sequence has already been recorded for the box.
pub fn record(box: Box) -> pog.Query(Box) {
  "INSERT INTO box_events (box, seq, root)
  VALUES ($1, $2, $3)
  ON CONFLICT DO NOTHING
  RETURNING box, seq, root"
  |> pog.query()
  |> pog.parameter(pog.text(box.name))
  |> pog.parameter(pog.int(box.sequence))
  |> pog.parameter(pog.text(v1.to_string(box.root)))
  |> pog.returning(decoder())
}

pub fn latest(name: String) -> pog.Query(Box) {
  "SELECT box, seq, root
  FROM box_events
  WHERE box = $1
  ORDER BY seq DESC
  LIMIT 1"
  |> pog.query()
  |> pog.parameter(pog.text(name))
  |> pog.returning(decoder())
}
