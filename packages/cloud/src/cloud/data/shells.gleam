//// A shell runs code in a box, what happened in it is in its journal, see `data/journal`.

import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import pog

pub type Shell {
  Shell(id: String, box: String)
}

fn decoder() -> decode.Decoder(Shell) {
  use id <- decode.field(0, decode.string)
  use box <- decode.field(1, decode.string)
  decode.success(Shell(id:, box:))
}

/// What a shell runs code for.
pub type For {
  /// Anyone, such as a person or a cron, who can send it any number of turns.
  Anyone
  /// A tool call, its code is the shell's only turn.
  /// A call made by a chat's llm has the chat, a call sent through the API has none.
  Call(chat: Option(String), call: String)
}

/// A new shell in the box.
/// A tool call of a chat already has a shell if no rows are returned, see `for_call`.
pub fn create(box: String, for: For) -> pog.Query(Shell) {
  let #(chat, call) = case for {
    Anyone -> #(None, None)
    Call(chat, call) -> #(chat, Some(call))
  }
  "INSERT INTO shells (box, chat, call) VALUES ($1, $2, $3)
  ON CONFLICT (chat, call) DO NOTHING
  RETURNING id, box"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.nullable(pog.text, chat))
  |> pog.parameter(pog.nullable(pog.text, call))
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

/// The shell of a chat's tool call.
pub fn for_call(chat: String, call: String) -> pog.Query(Shell) {
  "SELECT id, box FROM shells WHERE chat = $1 AND call = $2"
  |> pog.query()
  |> pog.parameter(pog.text(chat))
  |> pog.parameter(pog.text(call))
  |> pog.returning(decoder())
}

/// The shells of a chat, by the tool call they run if they run one.
pub fn of_chat(chat: String) -> pog.Query(#(Shell, Option(String))) {
  "SELECT id, box, call FROM shells WHERE chat = $1 ORDER BY created_at, id"
  |> pog.query()
  |> pog.parameter(pog.text(chat))
  |> pog.returning({
    use shell <- decode.then(decoder())
    use call <- decode.field(2, decode.optional(decode.string))
    decode.success(#(shell, call))
  })
}
