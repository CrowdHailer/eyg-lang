//// Entry module for slack channel and connection

import cloud/session
import cloud/slack/channel
import cloud/slack/client
import gleam/erlang/process.{type Subject}

pub fn start_channel(sessions: Subject(session.Message), token: String) {
  let assert Ok(identity) = client.auth_test(token)
  channel.start(token, identity, sessions)
}
