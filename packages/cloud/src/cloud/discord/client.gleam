//// Create an effectful client on the BEAM runtime.

import cloud/discord/api/client
import cloud/discord/api/schema
import cloud/system
import gleam/option.{type Option}

pub fn current_user(token: String) -> Result(schema.Identity, client.Failure) {
  client.current_user(client.Context(token:, fetch: system.fetch))(identity)
}

pub fn guild_channels(
  token: String,
  guild: String,
) -> Result(List(schema.Channel), client.Failure) {
  client.guild_channels(client.Context(token:, fetch: system.fetch), guild)(
    identity,
  )
}

pub fn create_message(
  token: String,
  channel: String,
  message: String,
  text: String,
) -> Result(Nil, client.Failure) {
  client.create_message(
    client.Context(token:, fetch: system.fetch),
    channel,
    message,
    text,
  )(identity)
}

pub fn channel_messages_since(
  token: String,
  channel: String,
  after: Option(String),
) -> Result(List(schema.Message), client.Failure) {
  client.channel_messages_since(
    client.Context(token:, fetch: system.fetch),
    channel,
    after,
  )(identity)
}

fn identity(x) {
  x
}
