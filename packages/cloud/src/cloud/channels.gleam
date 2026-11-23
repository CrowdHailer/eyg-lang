//// Conversations in chat channels, such as Discord channels, are durable chats in a box.
////
//// Each channel is bound to one chat, the binding is stored so the conversation continues after a restart.
//// A new channel gets a chat with the configured llm in the configured box.
//// Messages from a channel are handled one at a time in the order they arrived, by the channel's worker.
//// Text is sent to the chat and code, such as a fenced block, runs in a shell of the chat's own.

import cloud/apex/context.{type Context}
import cloud/box
import cloud/chats/chat
import cloud/data/chats.{type Chat}
import cloud/registry
import cloud/shells/turn
import gleam/erlang/process
import gleam/list
import gleam/option.{Some}
import gleam/result

pub type Channels {
  Channels(
    context: Context,
    // The id of the box new channels have their chat in.
    box: String,
    llm: String,
    workers: registry.Registry(fn(Nil) -> Nil),
  )
}

/// What a channel sends.
pub type Input {
  /// A message for the chat's llm.
  Text(String)
  /// Code to run in the box.
  Code(String)
}

/// Channels with chats in the named box.
pub fn start(
  context: Context,
  box: String,
  llm: String,
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

/// Handle a message from the channel, then reply with the llm's reply or what the code came to.
/// It runs after the channel's earlier messages, this returns before it runs.
pub fn deliver(
  channels: Channels,
  channel: String,
  input: Input,
  reply: fn(Result(turn.Outcome, box.Reason)) -> Nil,
) -> Nil {
  let worker =
    registry.lookup(channels.workers, channel, fn() { registry.serve(Nil) })
  process.send(worker, fn(state) {
    reply({
      use bound <- result.try(chat(channels, channel))
      case input {
        Text(message) ->
          chat.send(channels.context, bound, message)
          |> result.map(fn(replied) { #(replied, []) })
        Code(code) -> chat.run(channels.context, bound, code)
      }
    })
    state
  })
}

/// The chat the channel is bound to, a channel without one is bound to a new chat.
/// The binding is the chat's key, the channel.
pub fn chat(channels: Channels, channel: String) -> Result(Chat, box.Reason) {
  let Channels(context:, ..) = channels
  case chat.keyed(context, channel) {
    Ok(bound) -> Ok(bound)
    Error(box.Missing) ->
      case chat.create(context, channels.box, channels.llm, Some(channel)) {
        Ok(bound) -> Ok(bound)
        // If another process bound the channel first, its chat is used.
        Error(box.Taken) -> chat.keyed(context, channel)
        Error(reason) -> Error(reason)
      }
    Error(reason) -> Error(reason)
  }
}
