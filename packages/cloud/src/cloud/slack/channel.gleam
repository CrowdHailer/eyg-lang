//// One actor owns all cached channel histories and performs polling serially.

import cloud/beam/execute
import cloud/channel as routing
import cloud/session
import cloud/slack/api/schema
import cloud/slack/client
import cloud/slack/command
import cloud/slack/events
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
import gleam/time/timestamp

pub type Message {
  Poll
  Name(String, Subject(String))
  Channels(Subject(List(#(String, String))))
}

pub opaque type State {
  State(
    bot_token: String,
    subject: Subject(Message),
    identity: schema.Identity,
    conversations: Dict(String, Conversation),
    sessions: Subject(session.Message),
    hook: option.Option(fn(routing.Event) -> Nil),
    seen: Dict(String, Dict(String, events.Seen)),
    names: Dict(String, String),
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
) -> actor.StartResult(Subject(Message)) {
  start_with_hook(bot_token, identity, sessions, option.None)
}

/// Extend main's poller with configured handlers and reaction/thread triggers.
pub fn start_with_hook(bot_token, identity, sessions, hook) {
  actor.new_with_initialiser(1000, fn(subject) {
    // Load in the message handler: full histories can exceed the init timeout.
    process.send(subject, Poll)
    actor.initialised(State(
      bot_token,
      subject,
      identity,
      dict.new(),
      sessions,
      hook,
      dict.new(),
      dict.new(),
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
    Name(id, reply) -> {
      process.send(reply, dict.get(state.names, id) |> result.unwrap(id))
      actor.continue(state)
    }
    Channels(reply) -> {
      process.send(reply, dict.to_list(state.names))
      actor.continue(state)
    }
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
      let names =
        list.fold(channels, state.names, fn(names, channel) {
          dict.insert(names, channel.id, channel.name)
        })
      channels
      |> list.filter(fn(channel) { channel.is_member })
      |> list.fold(State(..state, names:), load_conversation)
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
      case loaded, state.hook {
        False, _ -> {
          let count = list.length(fresh)
          io.println("Loaded " <> int.to_string(count) <> " Slack messages")
        }
        True, option.Some(_) -> Nil
        True, option.None -> {
          let session_id =
            "Slack:" <> state.identity.team_id <> ":" <> channel.id
          list.each(fresh, fn(message) {
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
      let state =
        State(
          ..state,
          conversations: dict.insert(
            state.conversations,
            channel.id,
            Conversation(messages),
          ),
        )
      observe(state, channel.id, fresh, loaded)
    }
  }
}

fn observe(state: State, channel, fresh, loaded) {
  case state.hook {
    option.None -> state
    option.Some(emit) -> {
      let #(seconds, _) =
        timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
      let oldest = int.to_string(seconds - 3600) <> ".000000"
      let recent =
        client.conversations_history_since(
          state.bot_token,
          channel,
          option.Some(oldest),
        )
        |> result.unwrap([])
        |> list.reverse
      let messages = case loaded {
        True -> list.append(fresh, recent)
        False -> recent
      }
      let known = dict.get(state.seen, channel) |> result.unwrap(dict.new())
      let me = events.Me(state.identity.user_id, state.identity.bot_id)
      let #(posted, known, threads) =
        events.changes(channel, option.None, known, messages, me)
      let #(posted, known) =
        list.fold(threads, #(posted, known), fn(acc, thread) {
          let #(posted, known) = acc
          case
            client.conversations_replies_since(
              state.bot_token,
              channel,
              thread.0,
              option.Some(thread.1),
            )
          {
            Error(reason) -> {
              io.println_error("Slack thread: " <> string.inspect(reason))
              #(posted, known)
            }
            Ok(replies) -> {
              let replies =
                list.filter(replies, fn(reply) { reply.ts != thread.0 })
              let #(more, known, _) =
                events.changes(
                  channel,
                  option.Some(thread.0),
                  known,
                  replies,
                  me,
                )
              #(list.append(posted, more), known)
            }
          }
        })
      case loaded {
        True -> list.each(posted, emit)
        False -> Nil
      }
      State(..state, seen: dict.insert(state.seen, channel, known))
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
      case
        client.chat_post_message(
          token,
          channel,
          option.Some(thread_ts),
          text,
          color:,
        )
      {
        Ok(_) -> Nil
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
