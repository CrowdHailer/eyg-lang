//// Entry module for slack channel and connection

import cloud/session
import cloud/slack/channel
import cloud/slack/client
import cloud/slack/event
import cloud/trigger
import gleam/erlang/process.{type Subject}

/// The event argument supplied to Slack triggers. Triggers return {}.
pub fn trigger_type() {
  event.type_()
}

pub fn start_channel(
  sessions: Subject(session.Message),
  token: String,
  triggers: List(trigger.Checked),
) {
  let assert Ok(identity) = client.auth_test(token)
  channel.start(token, identity, sessions, triggers)
}
