//// Entry module for the Discord channel and connection.

import cloud/discord/channel
import cloud/discord/client
import cloud/discord/event
import cloud/session
import cloud/trigger
import gleam/erlang/process.{type Subject}

/// The event argument supplied to Discord triggers. Triggers return {}.
pub fn trigger_type() {
  event.type_()
}

pub fn start_channel(
  sessions: Subject(session.Message),
  token: String,
  guild: String,
  triggers: List(trigger.Checked),
) {
  let assert Ok(identity) = client.current_user(token)
  let assert Ok(guild) = client.guild(token, guild)
  channel.start(token, guild, identity.id, sessions, triggers)
}
