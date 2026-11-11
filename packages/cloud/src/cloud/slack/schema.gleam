//// Types and decoders for objects in the slack API.
//// Sorted alphabetically except errors that are last.

import cloud/jsonx
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None}

pub type Channel {
  Channel(
    id: String,
    name: String,
    is_member: Bool,
    is_private: Bool,
    is_archived: Bool,
  )
}

pub fn channel_decoder() -> decode.Decoder(Channel) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use is_private <- decode.field("is_private", decode.bool)
  use is_member <- decode.optional_field("is_member", is_private, decode.bool)
  use is_archived <- decode.field("is_archived", decode.bool)
  decode.success(Channel(id, name, is_member, is_private, is_archived))
}

pub type Channels {
  Channels(channels: List(Channel), next_cursor: String)
}

pub fn channels_decoder() -> decode.Decoder(Channels) {
  use channels <- decode.field("channels", decode.list(channel_decoder()))
  use next_cursor <- decode.optional_field(
    "response_metadata",
    "",
    decode.optional_field("next_cursor", "", decode.string, decode.success),
  )
  decode.success(Channels(channels, next_cursor))
}

pub type History {
  History(
    messages: List(Message),
    has_more: Bool,
    next_cursor: String,
    is_limited: Bool,
  )
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

pub type Identity {
  Identity(team: String, team_id: String, user_id: String, bot_id: String)
}

pub fn identity_decoder() -> decode.Decoder(Identity) {
  use team <- decode.field("team", decode.string)
  use team_id <- decode.field("team_id", decode.string)
  use user_id <- decode.field("user_id", decode.string)
  use bot_id <- decode.field("bot_id", decode.string)
  decode.success(Identity(team, team_id, user_id, bot_id))
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
  use data <- decode.then(jsonx.decoder())
  decode.success(Message(ts, data, thread_ts, reply_count, subtype, deleted_ts))
}

pub type ApiError {
  ApiError(error: String, needed: Option(String), provided: Option(String))
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
