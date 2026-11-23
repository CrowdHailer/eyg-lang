//// Entry module for the Discord channel and connection.

import cloud/channels
import cloud/discord/channel
import cloud/discord/client
import cloud/discord/event
import cloud/session
import cloud/trigger
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}

/// The event argument supplied to Discord triggers. Triggers return {}.
pub fn trigger_type() {
  event.type_()
}

/// Serve the selected channels of the guild, or all of them, with sessions from `channels`.
/// Triggers still run in `sessions`.
pub fn start_channel(
  sessions: Subject(session.Message),
  channels: channels.Channels,
  token: String,
  guild: String,
  selected: Option(List(String)),
  triggers: List(trigger.Checked),
) {
  let assert Ok(identity) = client.current_user(token)
  let assert Ok(guild) = client.guild(token, guild)
  channel.start(
    token,
    guild,
    identity.id,
    sessions,
    channels,
    selected,
    triggers,
  )
}
