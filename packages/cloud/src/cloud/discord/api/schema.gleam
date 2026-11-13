//// Types and decoders for objects in the Discord API.

import cloud/jsonx
import gleam/dynamic/decode
import gleam/json
import gleam/option

pub type Channel {
  Channel(id: String, name: String, kind: Int)
}

pub fn channel_decoder() -> decode.Decoder(Channel) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use kind <- decode.field("type", decode.int)
  decode.success(Channel(id, name, kind))
}

pub type Guild {
  Guild(id: String, name: String)
}

pub fn guild_decoder() -> decode.Decoder(Guild) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  decode.success(Guild(id, name))
}

pub type Identity {
  Identity(id: String, username: String)
}

pub fn identity_decoder() -> decode.Decoder(Identity) {
  use id <- decode.field("id", decode.string)
  use username <- decode.field("username", decode.string)
  decode.success(Identity(id, username))
}

/// Keep snowflakes as strings and preserve the complete message object.
pub type Message {
  Message(id: String, channel_id: String, data: json.Json)
}

pub fn message_decoder() -> decode.Decoder(Message) {
  use id <- decode.field("id", decode.string)
  use channel_id <- decode.field("channel_id", decode.string)
  use data <- decode.then(jsonx.decoder())
  decode.success(Message(id, channel_id, data))
}

pub type ApiError {
  ApiError(code: Int, message: String)
}

pub fn api_error_decoder() -> decode.Decoder(ApiError) {
  use code <- decode.field("code", decode.int)
  use message <- decode.field("message", decode.string)
  decode.success(ApiError(code, message))
}

/// A thread is a channel with a parent channel.
/// A thread started from a message has the same id as that message.
pub type Thread {
  Thread(id: String, parent_id: String)
}

pub fn thread_decoder() -> decode.Decoder(Thread) {
  use id <- decode.field("id", decode.string)
  use parent_id <- decode.field("parent_id", decode.string)
  decode.success(Thread(id, parent_id))
}

pub fn active_threads_decoder() -> decode.Decoder(List(Thread)) {
  decode.at(["threads"], decode.list(thread_decoder()))
}

pub type User {
  User(id: String, username: String, bot: Bool)
}

pub fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field("id", decode.string)
  use username <- decode.field("username", decode.string)
  use bot <- decode.optional_field("bot", False, decode.bool)
  decode.success(User(id, username, bot))
}

/// An emoji used in a reaction, `id` is set for custom emoji.
pub type Emoji {
  Emoji(id: option.Option(String), name: String)
}

pub fn emoji_decoder() -> decode.Decoder(Emoji) {
  use id <- decode.optional_field(
    "id",
    option.None,
    decode.optional(decode.string),
  )
  use name <- decode.field("name", decode.string)
  decode.success(Emoji(id, name))
}

pub type Reaction {
  Reaction(emoji: Emoji, count: Int)
}

pub fn reaction_decoder() -> decode.Decoder(Reaction) {
  use emoji <- decode.field("emoji", emoji_decoder())
  use count <- decode.field("count", decode.int)
  decode.success(Reaction(emoji, count))
}

/// The fields of a message that a channel plugin reads.
pub type Post {
  Post(
    id: String,
    channel_id: String,
    /// 0 is a default message and 19 a reply, other types are notices.
    kind: Int,
    author: User,
    webhook: Bool,
    content: String,
    reactions: List(Reaction),
  )
}

pub fn post_decoder() -> decode.Decoder(Post) {
  use id <- decode.field("id", decode.string)
  use channel_id <- decode.field("channel_id", decode.string)
  use kind <- decode.field("type", decode.int)
  use author <- decode.field("author", user_decoder())
  use webhook <- decode.optional_field(
    "webhook_id",
    option.None,
    decode.optional(decode.string),
  )
  use content <- decode.field("content", decode.string)
  use reactions <- decode.optional_field(
    "reactions",
    [],
    decode.list(reaction_decoder()),
  )
  decode.success(Post(
    id:,
    channel_id:,
    kind:,
    author:,
    webhook: option.is_some(webhook),
    content:,
    reactions:,
  ))
}
