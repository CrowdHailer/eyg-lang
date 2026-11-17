//// A session is a pointer into a thread, its history is the thread up to its head.

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

pub type Session {
  Session(id: String, box: String, head: Option(String))
}

fn decoder() -> decode.Decoder(Session) {
  use id <- decode.field(0, decode.string)
  use box <- decode.field(1, decode.string)
  use head <- decode.field(2, decode.optional(decode.string))
  decode.success(Session(id:, box:, head:))
}

pub fn create(box: String, head: Option(String)) -> pog.Query(Session) {
  "INSERT INTO sessions (box, head) VALUES ($1, $2) RETURNING id, box, head"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.nullable(pog.text, head))
  |> pog.returning(decoder())
}

pub fn get(id: String) -> pog.Query(Session) {
  "SELECT id, box, head FROM sessions WHERE id = $1"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning(decoder())
}

pub fn list(box: String) -> pog.Query(Session) {
  "SELECT id, box, head FROM sessions WHERE box = $1 ORDER BY created_at, id"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.returning(decoder())
}

/// Move the session's head, returns no rows if the head is no longer `from`.
pub fn move(
  id: String,
  from: Option(String),
  to: String,
) -> pog.Query(Session) {
  "UPDATE sessions SET head = $3
  WHERE id = $1 AND head IS NOT DISTINCT FROM $2
  RETURNING id, box, head"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.parameter(pog.nullable(pog.text, from))
  |> pog.parameter(pog.text(to))
  |> pog.returning(decoder())
}

/// A new session pointing at the same position in the thread as another.
pub fn fork(id: String) -> pog.Query(Session) {
  "INSERT INTO sessions (box, head)
  SELECT box, head FROM sessions WHERE id = $1
  RETURNING id, box, head"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning(decoder())
}

/// The most recent sessions in any box, with the name of the box if it has one.
/// Sessions in transient boxes are left out unless `transient` is true.
pub fn recent(
  limit: Int,
  transient: Bool,
) -> pog.Query(#(Session, Option(String))) {
  "SELECT s.id, s.box, s.head, b.name
  FROM sessions s JOIN boxes b ON b.id = s.box
  WHERE $2 OR b.name IS NOT NULL
  ORDER BY s.created_at DESC, s.id
  LIMIT $1"
  |> pog.query()
  |> pog.parameter(pog.int(limit))
  |> pog.parameter(pog.bool(transient))
  |> pog.returning({
    use session <- decode.then(decoder())
    use name <- decode.field(3, decode.optional(decode.string))
    decode.success(#(session, name))
  })
}
