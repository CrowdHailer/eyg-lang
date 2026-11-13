//// Types and decoders for objects in the Discord API.

import cloud/jsonx
import gleam/dynamic/decode
import gleam/json

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
