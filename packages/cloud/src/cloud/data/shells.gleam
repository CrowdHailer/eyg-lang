//// A shell runs code in a box, what happened in it is in its journal, see `data/journal`.

import gleam/dynamic/decode
import pog

pub type Shell {
  Shell(id: String, box: String)
}

fn decoder() -> decode.Decoder(Shell) {
  use id <- decode.field(0, decode.string)
  use box <- decode.field(1, decode.string)
  decode.success(Shell(id:, box:))
}

/// A new shell in the box.
pub fn create(box: String) -> pog.Query(Shell) {
  "INSERT INTO shells (box) VALUES ($1) RETURNING id, box"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.returning(decoder())
}

pub fn get(id: String) -> pog.Query(Shell) {
  "SELECT id, box FROM shells WHERE id = $1"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning(decoder())
}

pub fn list(box: String) -> pog.Query(Shell) {
  "SELECT id, box FROM shells WHERE box = $1 ORDER BY created_at, id"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.returning(decoder())
}
