//// A shell's journal is what happened in it, in order. Entries are only ever appended.
//// An entry is JSON, an input also records the box event its segment of code starts from.

import cloud/data/boxes
import eyg/ir/dag_json
import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import multiformats/cid/v1
import pog

/// An entry to append.
pub type Row {
  Row(seq: Int, start: Option(Int), entry: String)
}

/// Append an entry, it fails if the shell already has an entry with the sequence,
/// so two processes cannot both continue a shell.
pub fn append(shell: String, box: String, row: Row) -> pog.Query(Nil) {
  "INSERT INTO journal (shell, box, seq, start, entry) VALUES ($1, $2, $3, $4, $5::jsonb)"
  |> pog.query()
  |> pog.parameter(pog.text(shell))
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.int(row.seq))
  |> pog.parameter(pog.nullable(pog.int, row.start))
  |> pog.parameter(pog.text(row.entry))
}

/// An entry as it was recorded. An input has the box event it starts from and the root of the box there.
pub type Recorded {
  Recorded(
    seq: Int,
    /// When it was recorded, in microseconds since the Unix epoch.
    at: Int,
    start: Option(#(Int, v1.Cid)),
    entry: String,
  )
}

/// Every entry of the shell, in order.
pub fn entries(shell: String) -> pog.Query(Recorded) {
  {
    "SELECT j.seq, (EXTRACT(EPOCH FROM j.recorded_at) * 1000000)::BIGINT, j.start, root.root, j.entry::TEXT
  FROM journal j
  LEFT "
    <> boxes.join_root("j.box", "j.start")
    <> "
  WHERE j.shell = $1
  ORDER BY j.seq"
  }
  |> pog.query()
  |> pog.parameter(pog.text(shell))
  |> pog.returning({
    use seq <- decode.field(0, decode.int)
    use at <- decode.field(1, decode.int)
    use start <- decode.field(2, decode.optional(decode.int))
    use root <- decode.field(3, decode.optional(decode.string))
    use entry <- decode.field(4, decode.string)
    case start, root {
      Some(start), Some(root) ->
        case v1.from_string(root) {
          Ok(#(root, _)) ->
            decode.success(Recorded(
              seq:,
              at:,
              start: Some(#(start, root)),
              entry:,
            ))
          Error(_) ->
            decode.failure(
              Recorded(
                seq:,
                at:,
                start: Some(#(start, dag_json.vacant_cid)),
                entry:,
              ),
              "CID",
            )
        }
      _, _ -> decode.success(Recorded(seq:, at:, start: None, entry:))
    }
  })
}

/// Copy the entries of a shell to another in the same box.
pub fn copy(from: String, to: String) -> pog.Query(Nil) {
  "INSERT INTO journal (shell, box, seq, start, entry, recorded_at)
  SELECT $2, box, seq, start, entry, recorded_at FROM journal WHERE shell = $1"
  |> pog.query()
  |> pog.parameter(pog.text(from))
  |> pog.parameter(pog.text(to))
}
