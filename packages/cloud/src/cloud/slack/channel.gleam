//// One actor owns all cached channel histories and performs polling serially.

import cloud/beam/execute
import cloud/slack/api/schema
import cloud/slack/client
import cloud/slack/command
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/set
import gleam/string

pub type Message {
  Poll
}

pub opaque type State {
  State(
    bot_token: String,
    subject: Subject(Message),
    bot_user: String,
    conversations: Dict(String, Conversation),
  )
}

/// id in map key
pub type Conversation {
  Conversation(history: List(schema.Message))
}

pub fn start(
  bot_token: String,
  bot_user: String,
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(1000, fn(subject) {
    // Load in the message handler: full histories can exceed the init timeout.
    process.send(subject, Poll)
    actor.initialised(State(bot_token, subject, bot_user, dict.new()))
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    Poll -> {
      let state = poll(state)
      // Schedule after completion so slow requests never build up poll messages.
      let _ = process.send_after(state.subject, 2000, Poll)
      actor.continue(state)
    }
  }
}

fn poll(state: State) -> State {
  case client.conversations_list(state.bot_token) {
    Error(reason) -> {
      io.println_error("Slack channels: " <> string.inspect(reason))
      state
    }
    Ok(channels) -> {
      channels
      |> list.filter(fn(channel) { channel.is_member })
      |> list.fold(state, load_conversation)
    }
  }
}

fn load_conversation(state: State, channel: schema.Channel) -> State {
  let #(previous, loaded) = case dict.get(state.conversations, channel.id) {
    Ok(Conversation(history:)) -> #(history, True)
    Error(Nil) -> #([], False)
  }
  let oldest =
    list.first(previous)
    |> result.map(fn(message) { message.ts })
    |> option.from_result
  let messages =
    client.conversations_history_since(state.bot_token, channel.id, oldest)
  case messages {
    Error(reason) -> {
      io.println_error("Slack " <> channel.id <> ": " <> string.inspect(reason))
      // Keep the previous timestamp, so a failed page is retried next poll.
      state
    }
    Ok(messages) -> {
      let known = set.from_list(list.map(previous, fn(message) { message.ts }))
      let #(fresh, _) =
        list.fold(messages, #([], known), fn(acc, message) {
          let #(fresh, known) = acc
          case set.contains(known, message.ts) {
            True -> acc
            False -> #([message, ..fresh], set.insert(known, message.ts))
          }
        })
      // History is newest-first; `fresh` is reversed for chronological logging.
      case loaded {
        False -> {
          let count = list.length(fresh)
          io.println("Loaded " <> int.to_string(count) <> " Slack messages")
        }
        True ->
          list.each(fresh, fn(message) {
            case command.source(message.data, state.bot_user) {
              Error(Nil) -> Nil
              Ok(code) ->
                case execute.block(code) {
                  Ok(value) ->
                    io.println("Slack " <> channel.id <> ": " <> value)
                  Error(reason) ->
                    io.println_error("Slack " <> channel.id <> ": " <> reason)
                }
            }
          })
      }
      let messages = list.append(list.reverse(fresh), previous)
      State(
        ..state,
        conversations: dict.insert(
          state.conversations,
          channel.id,
          Conversation(messages),
        ),
      )
    }
  }
}
