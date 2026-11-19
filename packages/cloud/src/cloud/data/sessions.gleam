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

/// A session that chats with `llm`, or a shell without one.
pub fn create(
  box: String,
  head: Option(String),
  llm: Option(String),
) -> pog.Query(Session) {
  "INSERT INTO sessions (box, head, llm) VALUES ($1, $2, $3) RETURNING id, box, head"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.nullable(pog.text, head))
  |> pog.parameter(pog.nullable(pog.text, llm))
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
  "INSERT INTO sessions (box, head, llm)
  SELECT box, head, llm FROM sessions WHERE id = $1
  RETURNING id, box, head"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning(decoder())
}

/// A session as it is listed.
pub type Listed {
  Listed(
    session: Session,
    /// The name of its box, a transient box has none.
    box: Option(String),
    /// The llm it chats with, a shell has none.
    llm: Option(String),
    /// What made it.
    by: Creator,
  )
}

/// What made a session.
pub type Creator {
  /// A person, from the web interface or the API.
  Person
  /// The cron with this name in the session's box.
  Cron(String)
  /// A channel, such as one in Discord, that the session replies to.
  Channel
}

/// The most recent sessions in any box.
/// Sessions in transient boxes are left out unless `transient` is true.
pub fn recent(limit: Int, transient: Bool) -> pog.Query(Listed) {
  "SELECT s.id, s.box, s.head, b.name, s.llm,
    (SELECT c.name FROM crons c WHERE c.session = s.id LIMIT 1),
    EXISTS (SELECT 1 FROM channel_sessions c WHERE c.session = s.id)
  FROM sessions s JOIN boxes b ON b.id = s.box
  WHERE $2 OR b.name IS NOT NULL
  ORDER BY s.created_at DESC, s.id
  LIMIT $1"
  |> pog.query()
  |> pog.parameter(pog.int(limit))
  |> pog.parameter(pog.bool(transient))
  |> pog.returning({
    use session <- decode.then(decoder())
    use box <- decode.field(3, decode.optional(decode.string))
    use llm <- decode.field(4, decode.optional(decode.string))
    use cron <- decode.field(5, decode.optional(decode.string))
    use channel <- decode.field(6, decode.bool)
    let by = case cron, channel {
      option.Some(name), _ -> Cron(name)
      option.None, True -> Channel
      option.None, False -> Person
    }
    decode.success(Listed(session:, box:, llm:, by:))
  })
}

/// The session a channel is bound to.
pub fn bound(channel: String) -> pog.Query(Session) {
  "SELECT s.id, s.box, s.head
  FROM channel_sessions c JOIN sessions s ON s.id = c.session
  WHERE c.channel = $1"
  |> pog.query()
  |> pog.parameter(pog.text(channel))
  |> pog.returning(decoder())
}

/// Bind a channel to a session, returns no rows if the channel is already bound.
pub fn bind(channel: String, session: String) -> pog.Query(String) {
  "INSERT INTO channel_sessions (channel, session) VALUES ($1, $2)
  ON CONFLICT DO NOTHING
  RETURNING session"
  |> pog.query()
  |> pog.parameter(pog.text(channel))
  |> pog.parameter(pog.text(session))
  |> pog.returning(decode.at([0], decode.string))
}
