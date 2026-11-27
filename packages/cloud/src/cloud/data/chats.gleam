//// A chat is a conversation with an llm about a box, what happened in it is in its journal.
//// The code of the llm's tool calls runs in shells, see `data/shells`.

import gleam/dynamic/decode
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

/// A new chat in the box.
pub fn create(box: String, llm: String) -> pog.Query(Chat) {
  "INSERT INTO chats (box, llm) VALUES ($1, $2) RETURNING id, box, llm"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.text(llm))
  |> pog.returning(decoder())
}

pub fn get(id: String) -> pog.Query(Chat) {
  "SELECT id, box, llm FROM chats WHERE id = $1"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning(decoder())
}

pub fn list(box: String) -> pog.Query(Chat) {
  "SELECT id, box, llm FROM chats WHERE box = $1 ORDER BY created_at, id"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.returning(decoder())
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
