//// A chat is a conversation with an llm about a box, what happened in it is in its journal.
//// The code of the llm's tool calls runs in shells, see `data/shells`.

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

pub type Chat {
  Chat(id: String, box: String, llm: String)
}

fn decoder() -> decode.Decoder(Chat) {
  use id <- decode.field(0, decode.string)
  use box <- decode.field(1, decode.string)
  use llm <- decode.field(2, decode.string)
  decode.success(Chat(id:, box:, llm:))
}

/// A new chat in the box. `key` identifies what it belongs to outside the service,
/// returns no rows if a chat already has the key.
pub fn create(
  box: String,
  llm: String,
  key: Option(String),
) -> pog.Query(Chat) {
  "INSERT INTO chats (box, llm, key) VALUES ($1, $2, $3)
  ON CONFLICT (key) DO NOTHING
  RETURNING id, box, llm"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.text(llm))
  |> pog.parameter(pog.nullable(pog.text, key))
  |> pog.returning(decoder())
}

pub fn get(id: String) -> pog.Query(Chat) {
  "SELECT id, box, llm FROM chats WHERE id = $1"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning(decoder())
}

/// The chat with the key.
pub fn keyed(key: String) -> pog.Query(Chat) {
  "SELECT id, box, llm FROM chats WHERE key = $1"
  |> pog.query()
  |> pog.parameter(pog.text(key))
  |> pog.returning(decoder())
}

pub fn list(box: String) -> pog.Query(Chat) {
  "SELECT id, box, llm FROM chats WHERE box = $1 ORDER BY created_at, id"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.returning(decoder())
}

/// A chat as it is listed.
pub type Listed {
  Listed(
    chat: Chat,
    /// The name of its box, a transient box has none.
    box: Option(String),
    /// Whether a channel, such as a Discord thread, made it, rather than a person.
    channel: Bool,
    /// When it was made, in microseconds since the Unix epoch.
    at: Int,
  )
}

/// The most recent chats in any box.
/// Chats in transient boxes are left out unless `transient` is true.
pub fn recent(limit: Int, transient: Bool) -> pog.Query(Listed) {
  "SELECT c.id, c.box, c.llm, b.name, c.key,
    (EXTRACT(EPOCH FROM c.created_at) * 1000000)::BIGINT
  FROM chats c JOIN boxes b ON b.id = c.box
  WHERE $2 OR b.name IS NOT NULL
  ORDER BY c.created_at DESC, c.id
  LIMIT $1"
  |> pog.query()
  |> pog.parameter(pog.int(limit))
  |> pog.parameter(pog.bool(transient))
  |> pog.returning({
    use chat <- decode.then(decoder())
    use box <- decode.field(3, decode.optional(decode.string))
    use key <- decode.field(4, decode.optional(decode.string))
    use at <- decode.field(5, decode.int)
    decode.success(Listed(chat:, box:, channel: key != option.None, at:))
  })
}

/// Append an entry to the chat's journal.
pub fn append(chat: String, entry: String) -> pog.Query(Nil) {
  "INSERT INTO chat_journal (chat, entry) VALUES ($1, $2::jsonb)"
  |> pog.query()
  |> pog.parameter(pog.text(chat))
  |> pog.parameter(pog.text(entry))
}

/// An entry as it was recorded.
pub type Recorded {
  Recorded(
    /// When it was recorded, in microseconds since the Unix epoch.
    at: Int,
    entry: String,
  )
}

/// Every entry of the chat, in order.
pub fn entries(chat: String) -> pog.Query(Recorded) {
  "SELECT (EXTRACT(EPOCH FROM recorded_at) * 1000000)::BIGINT, entry::TEXT
  FROM chat_journal WHERE chat = $1 ORDER BY id"
  |> pog.query()
  |> pog.parameter(pog.text(chat))
  |> pog.returning({
    use at <- decode.field(0, decode.int)
    use entry <- decode.field(1, decode.string)
    decode.success(Recorded(at:, entry:))
  })
}
