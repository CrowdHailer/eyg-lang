import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/string

pub type Identity {
  Identity(team: String, team_id: String, user_id: String, bot_id: String)
}

pub type ApiError {
  ApiError(error: String, needed: Option(String), provided: Option(String))
}

/// History messages do not contain a channel ID.
pub type Message {
  Message(
    ts: String,
    data: json.Json,
    thread_ts: Option(String),
    reply_count: Int,
    subtype: Option(String),
    deleted_ts: Option(String),
  )
}

pub type History {
  History(
    messages: List(Message),
    has_more: Bool,
    next_cursor: String,
    is_limited: Bool,
  )
}

pub fn identity_decoder() -> decode.Decoder(Identity) {
  use team <- decode.field("team", decode.string)
  use team_id <- decode.field("team_id", decode.string)
  use user_id <- decode.field("user_id", decode.string)
  use bot_id <- decode.field("bot_id", decode.string)
  decode.success(Identity(team, team_id, user_id, bot_id))
}

pub fn api_error_decoder() -> decode.Decoder(ApiError) {
  use error <- decode.field("error", decode.string)
  use needed <- decode.optional_field(
    "needed",
    None,
    decode.optional(decode.string),
  )
  use provided <- decode.optional_field(
    "provided",
    None,
    decode.optional(decode.string),
  )
  decode.success(ApiError(error, needed, provided))
}

pub fn message_decoder() -> decode.Decoder(Message) {
  use ts <- decode.field("ts", decode.string)
  use thread_ts <- decode.optional_field(
    "thread_ts",
    None,
    decode.optional(decode.string),
  )
  use reply_count <- decode.optional_field("reply_count", 0, decode.int)
  use subtype <- decode.optional_field(
    "subtype",
    None,
    decode.optional(decode.string),
  )
  use deleted_ts <- decode.optional_field(
    "deleted_ts",
    None,
    decode.optional(decode.string),
  )
  use data <- decode.then(json_decoder())
  decode.success(Message(ts, data, thread_ts, reply_count, subtype, deleted_ts))
}

pub fn history_decoder() -> decode.Decoder(History) {
  use messages <- decode.field("messages", decode.list(message_decoder()))
  use has_more <- decode.field("has_more", decode.bool)
  use is_limited <- decode.optional_field("is_limited", False, decode.bool)
  use next_cursor <- decode.optional_field(
    "response_metadata",
    "",
    decode.optional_field("next_cursor", "", decode.string, decode.success),
  )
  decode.success(History(messages, has_more, next_cursor, is_limited))
}

// Preserve fields we don't interpret, including bot messages and attachments.
fn json_decoder() -> decode.Decoder(json.Json) {
  decode.one_of(decode.string |> decode.map(json.string), or: [
    decode.int |> decode.map(json.int),
    decode.float |> decode.map(json.float),
    decode.bool |> decode.map(json.bool),
    decode.list(decode.recursive(json_decoder))
      |> decode.map(json.preprocessed_array),
    decode.dict(decode.string, decode.recursive(json_decoder))
      |> decode.map(fn(fields) {
        // Stable object-key order makes version comparison independent of the
        // order Slack used when serializing otherwise identical objects.
        fields
        |> dict.to_list
        |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
        |> json.object
      }),
  ])
  |> decode.optional
  |> decode.map(json.nullable(_, fn(x) { x }))
}
