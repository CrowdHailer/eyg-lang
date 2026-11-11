//// Create an effectful client on the BEAM runtime

import cloud/slack/api/client
import cloud/slack/api/schema
import cloud/system
import gleam/option.{type Option}

pub fn auth_test(token: String) -> Result(schema.Identity, client.Failure) {
  client.auth_test(client.Context(token:, fetch: system.fetch))(identity)
}

pub fn chat_post_message(
  token: String,
  channel: String,
  thread_ts: String,
  text: String,
  color color: Option(String),
) -> Result(Nil, client.Failure) {
  client.chat_post_message(
    client.Context(token:, fetch: system.fetch),
    channel,
    thread_ts,
    text,
    color:,
  )(identity)
}

pub fn conversations_list(
  token: String,
) -> Result(List(schema.Channel), client.Failure) {
  client.conversations_list(client.Context(token:, fetch: system.fetch))(
    identity,
  )
}

pub fn conversations_history_since(
  token: String,
  channel_id: String,
  oldest: Option(String),
) -> Result(List(schema.Message), client.Failure) {
  client.conversations_history_since(
    client.Context(token:, fetch: system.fetch),
    channel_id,
    oldest,
  )(identity)
}

fn identity(x) {
  x
}
