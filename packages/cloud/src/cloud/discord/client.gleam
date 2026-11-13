//// Create an effectful client on the BEAM runtime.

import cloud/discord/api/client
import cloud/discord/api/schema
import cloud/system
import gleam/option.{type Option}

fn context(token) {
  client.Context(token:, fetch: system.fetch)
}

pub fn create_message(token, channel, message, text) {
  client.create_message(context(token), channel, message, text)(identity)
}

pub fn current_user(token: String) -> Result(schema.Identity, client.Failure) {
  client.current_user(context(token))(identity)
}

pub fn guild(
  token: String,
  guild: String,
) -> Result(schema.Guild, client.Failure) {
  client.guild(client.Context(token:, fetch: system.fetch), guild)(identity)
}

pub fn guild_channels(
  token: String,
  guild: String,
) -> Result(List(schema.Channel), client.Failure) {
  client.guild_channels(context(token), guild)(identity)
}

pub fn channel_messages_since(
  token: String,
  channel: String,
  after: Option(String),
) -> Result(List(schema.Message), client.Failure) {
  client.channel_messages_since(context(token), channel, after)(identity)
}

pub fn post_message(
  token: String,
  channel: String,
  text: String,
) -> Result(String, client.Failure) {
  client.post_message(context(token), channel, text)(identity)
}

pub fn recent_messages(
  token: String,
  channel: String,
  limit: Int,
) -> Result(List(schema.Post), client.Failure) {
  client.recent_messages(context(token), channel, limit)(identity)
}

pub fn get_message(
  token: String,
  channel: String,
  message: String,
) -> Result(schema.Post, client.Failure) {
  client.get_message(context(token), channel, message)(identity)
}

pub fn active_threads(
  token: String,
  guild: String,
) -> Result(List(schema.Thread), client.Failure) {
  client.active_threads(context(token), guild)(identity)
}

pub fn start_thread(
  token: String,
  channel: String,
  message: String,
  name: String,
) -> Result(Nil, client.Failure) {
  client.start_thread(context(token), channel, message, name)(identity)
}

pub fn reactions(
  token: String,
  channel: String,
  message: String,
  emoji: String,
) -> Result(List(schema.User), client.Failure) {
  client.reactions(context(token), channel, message, emoji)(identity)
}

fn identity(x) {
  x
}
