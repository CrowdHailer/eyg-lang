//// One actor owns all cached channel histories and performs polling serially.

import cloud/beam/execute
import cloud/session
import cloud/slack/api/schema
import cloud/slack/client
import cloud/slack/command
import cloud/slack/event
import cloud/trigger
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
    identity: schema.Identity,
    conversations: Dict(String, Conversation),
    sessions: Subject(session.Message),
    triggers: List(trigger.Checked),
  )
}

/// id in map key
pub type Conversation {
  Conversation(history: List(schema.Message))
}

pub fn start(
  bot_token: String,
  identity: schema.Identity,
  sessions: Subject(session.Message),
  triggers: List(trigger.Checked),
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(1000, fn(subject) {
    // Load in the message handler: full histories can exceed the init timeout.
    process.send(subject, Poll)
    actor.initialised(State(
      bot_token,
      subject,
      identity,
      dict.new(),
      sessions,
      triggers,
    ))
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
      // History is newest-first; process `fresh` in chronological order.
      case loaded {
        False -> {
          let count = list.length(fresh)
          io.println("Loaded " <> int.to_string(count) <> " Slack messages")
        }
        True -> {
          let session_id =
            "Slack:" <> state.identity.team_id <> ":" <> channel.id
          list.each(fresh, fn(message) {
            case event.from_message(channel.id, message) {
              Ok(event) -> {
                let value = event.to_eyg(channel.name, event)
                list.each(state.triggers, fn(function) {
                  process.send(state.sessions, session.Trigger(function, value))
                })
              }
              Error(reason) -> io.println_error(reason)
            }
            // Conversation ID: channel.id; workspace ID: state.identity.team_id.
            // The optional thread ID is message.thread_ts (Option(String)).
            case command.payload(message.data, state.identity.user_id) {
              Error(Nil) -> Nil
              Ok(payload) -> {
                // Reply in the existing thread, or start one on this message.
                let ts = option.unwrap(message.thread_ts, message.ts)
                process.send(
                  state.sessions,
                  session.Message(id: session_id, payload:, print: print_output(
                    state.bot_token,
                    channel.id,
                    ts,
                    _,
                  )),
                )
              }
            }
          })
        }
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

fn print_output(
  token: String,
  channel: String,
  thread_ts: String,
  output: execute.Output,
) {
  let #(text, color) = case output {
    execute.StandardOut(text) -> #(text, option.None)
    execute.StandardError(text) -> #(text, option.Some("warning"))
  }
  case string.trim(text) {
    "" -> Nil
    _ ->
      case client.chat_post_message(token, channel, thread_ts, text, color:) {
        Ok(Nil) -> Nil
        Error(reason) ->
          io.println_error(
            "Slack "
            <> channel
            <> " thread "
            <> thread_ts
            <> ": "
            <> string.inspect(reason),
          )
      }
  }
}
