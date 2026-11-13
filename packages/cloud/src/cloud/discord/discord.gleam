//// Entry module for the Discord channel and connection.

import cloud/discord/channel
import cloud/discord/client
import cloud/session
import gleam/erlang/process.{type Subject}

pub fn start_channel(
  sessions: Subject(session.Message),
  token: String,
  guild: String,
) {
  let assert Ok(identity) = client.current_user(token)
  let assert Ok(guild) = client.guild(token, guild)
  channel.start(token, guild, identity.id, sessions)
}
