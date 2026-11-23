//// A box is stored as its events, each one sets the root of its file system, its name, or both.
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

/// Join the root of the box at the event `seq` as `root.root`, it is set by the latest event at or before it that has one.
/// `box` and `seq` are SQL expressions.
pub fn join_root(box: String, seq: String) -> String {
  "JOIN LATERAL (
    SELECT root FROM box_events
    WHERE box = " <> box <> " AND seq <= " <> seq <> " AND root IS NOT NULL
    ORDER BY seq DESC LIMIT 1
  ) root ON TRUE"
}

/// A new box starting at `root`, returns no rows when the name is taken.
pub fn create(name: Option(String), root: v1.Cid) -> pog.Query(Box) {
  "WITH box AS (
    INSERT INTO boxes (name) VALUES ($1) ON CONFLICT DO NOTHING RETURNING id, name
  )
  INSERT INTO box_events (box, seq, root, name)
  SELECT id, 1, $2, name FROM box
  RETURNING box, $1::TEXT, seq, root"
  |> pog.query()
  |> pog.parameter(pog.nullable(pog.text, name))
  |> pog.parameter(pog.text(v1.to_string(root)))
  |> pog.returning(decoder())
}

/// Move the box to a new root, returns no rows when the sequence has already been recorded for the box.
pub fn record(box: Box) -> pog.Query(Box) {
  "INSERT INTO box_events (box, seq, root)
  VALUES ($1, $2, $3)
  ON CONFLICT DO NOTHING
  RETURNING box, $4::TEXT, seq, root"
  |> pog.query()
  |> pog.parameter(pog.text(box.id))
  |> pog.parameter(pog.int(box.sequence))
  |> pog.parameter(pog.text(v1.to_string(box.root)))
  |> pog.parameter(pog.nullable(pog.text, box.name))
  |> pog.returning(decoder())
}

/// The latest state of the box.
pub fn latest(id: String) -> pog.Query(Box) {
  { "SELECT b.id, b.name, e.seq, root.root
  FROM boxes b
  JOIN LATERAL (
    SELECT seq FROM box_events WHERE box = b.id ORDER BY seq DESC LIMIT 1
  ) e ON TRUE
  " <> join_root("b.id", "e.seq") <> "
  WHERE b.id = $1" }
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning(decoder())
}

/// The latest state of every named box, in order of name.
pub fn named() -> pog.Query(Box) {
  { "SELECT b.id, b.name, e.seq, root.root
  FROM boxes b
  JOIN LATERAL (
    SELECT seq FROM box_events WHERE box = b.id ORDER BY seq DESC LIMIT 1
  ) e ON TRUE
  " <> join_root("b.id", "e.seq") <> "
  WHERE b.name IS NOT NULL
  ORDER BY b.name" }
  |> pog.query()
  |> pog.returning(decoder())
}
