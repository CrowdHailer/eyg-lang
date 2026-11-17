//// Conversations in chat channels, such as Discord channels, run in durable sessions in a box.
////
//// Each channel is bound to one session, the binding is stored so the conversation continues after a restart.
//// A new channel gets a session in the configured box, it chats with the configured llm if there is one.
//// Messages from a channel are handled one at a time in the order they arrived, by the channel's worker,
//// they run with the same turns as the API, so files, history and recovery are the same.

import cloud/apex/context.{type Context}
import cloud/box
import cloud/data/db
import cloud/data/sessions.{type Session}
import cloud/registry
import cloud/sessions/turn
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import pog

pub type Channels {
  Channels(
    context: Context,
    // The id of the box new channels have their session in.
    box: String,
    llm: Option(String),
    workers: registry.Registry(fn(Nil) -> Nil),
  )
}

/// Channels with sessions in the named box.
pub fn start(
  context: Context,
  box: String,
  llm: Option(String),
) -> Result(Channels, String) {
  use boxes <- result.try(
    box.named(context) |> result.replace_error("the boxes could not be listed"),
  )
  use box <- result.try(
    list.find(boxes, fn(found) { found.name == Some(box) })
    |> result.map(fn(found) { found.id })
    |> result.replace_error("there is no box named " <> box),
  )
  use workers <- result.map(
    registry.start() |> result.replace_error("the workers could not start"),
  )
  Channels(context, box, llm, workers.data)
}

/// Run a turn for a message from the channel, then reply with its outcome.
/// It runs after the channel's earlier messages, this returns before it runs.
pub fn deliver(
  channels: Channels,
  channel: String,
  input: turn.Input,
  reply: fn(Result(turn.Outcome, box.Reason)) -> Nil,
) -> Nil {
  let worker =
    registry.lookup(channels.workers, channel, fn() { registry.serve(Nil) })
  process.send(worker, fn(state) {
    reply({
      use session <- result.try(session(channels, channel))
      turn.send(channels.context, session, input)
    })
    state
  })
}

/// The session the channel is bound to, a channel without one is bound to a new session.
pub fn session(
  channels: Channels,
  channel: String,
) -> Result(Session, box.Reason) {
  let Channels(context:, ..) = channels
  use bound <- result.try(query(sessions.bound(channel), context))
  case bound {
    [session] -> Ok(session)
    _ -> {
      use session <- result.try(turn.start(context, channels.box, channels.llm))
      use _ <- result.try(query(sessions.bind(channel, session.id), context))
      // If another process bound the channel first, its session is used.
      use bound <- result.try(query(sessions.bound(channel), context))
      case bound {
        [session] -> Ok(session)
        _ -> Error(box.Failed("the channel could not be bound"))
      }
    }
  }
}

fn query(query, context: Context) {
  db.execute(query, context.db)
  |> result.map(fn(returned: pog.Returned(_)) { returned.rows })
  |> result.map_error(fn(reason) { box.Failed(string.inspect(reason)) })
}
