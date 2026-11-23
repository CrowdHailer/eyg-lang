//// The secrets of each box, by name.

import gleam/dynamic/decode
import pog

/// Add a secret, or replace the secret with the same name.
pub fn set(box: String, name: String, value: String) -> pog.Query(Nil) {
  "INSERT INTO box_secrets (box, name, value) VALUES ($1, $2, $3)
  ON CONFLICT (box, name) DO UPDATE SET value = EXCLUDED.value"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.text(name))
  |> pog.parameter(pog.text(value))
}

pub fn delete(box: String, name: String) -> pog.Query(Nil) {
  "DELETE FROM box_secrets WHERE box = $1 AND name = $2"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.text(name))
}

/// Every secret of the box with its value, in order of name.
pub fn all(box: String) -> pog.Query(#(String, String)) {
  "SELECT name, value FROM box_secrets WHERE box = $1 ORDER BY name"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.returning({
    use name <- decode.field(0, decode.string)
    use value <- decode.field(1, decode.string)
    decode.success(#(name, value))
  })
}

/// Give a box the secrets of another.
pub fn copy(from: String, to: String) -> pog.Query(Nil) {
  "INSERT INTO box_secrets (box, name, value)
  SELECT $2, name, value FROM box_secrets WHERE box = $1"
  |> pog.query()
  |> pog.parameter(pog.text(from))
  |> pog.parameter(pog.text(to))
}
