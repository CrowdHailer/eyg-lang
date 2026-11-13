//// One actor discovers guild channels and polls their histories serially.

import cloud/beam/execute
import cloud/discord/api/client as api
import cloud/discord/api/operations
import cloud/discord/api/schema
import cloud/discord/client
import cloud/discord/command
import cloud/discord/event
import cloud/session
import cloud/trigger
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
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
    guild: schema.Guild,
    subject: Subject(Message),
    bot_user: String,
    conversations: Dict(String, List(schema.Message)),
    sessions: Subject(session.Message),
    triggers: List(trigger.Checked),
  )
}

pub fn start(
  bot_token: String,
  guild: schema.Guild,
  bot_user: String,
  sessions: Subject(session.Message),
  triggers: List(trigger.Checked),
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(1000, fn(subject) {
    // Full histories can exceed the init timeout; load in the message handler.
    process.send(subject, Poll)
    actor.initialised(State(
      bot_token,
      guild,
      subject,
      bot_user,
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
      let _ = process.send_after(state.subject, 5000, Poll)
      actor.continue(state)
    }
  }
}

fn poll(state: State) -> State {
  case client.guild_channels(state.bot_token, state.guild.id) {
    Error(reason) -> {
      report_failure("channels", reason)
      state
    }
    Ok(channels) -> list.fold(channels, state, load_conversation)
  }
}

fn load_conversation(state: State, channel: schema.Channel) -> State {
  let #(previous, loaded) = case dict.get(state.conversations, channel.id) {
    Ok(history) -> #(history, True)
    Error(Nil) -> #([], False)
  }
  let after =
    list.first(previous)
    |> result.map(fn(message) { message.id })
    |> option.from_result
  let messages =
    client.channel_messages_since(state.bot_token, channel.id, after)
  case messages {
    Error(reason) -> {
      report_failure(channel.id, reason)
      // Keep the previous cursor so a failed page is retried next poll.
      state
    }
    Ok(messages) -> {
      let known = set.from_list(list.map(previous, fn(message) { message.id }))
      let #(fresh, _) =
        list.fold(messages, #([], known), fn(acc, message) {
          let #(fresh, known) = acc
          case set.contains(known, message.id) {
            True -> acc
            False -> #([message, ..fresh], set.insert(known, message.id))
          }
        })
      // History is newest-first; process `fresh` in chronological order.
      case loaded {
        False -> {
          io.println(
            "Loaded "
            <> int.to_string(list.length(fresh))
            <> " Discord messages",
          )
        }
        True -> {
          let session_id = "Discord:" <> state.guild.id <> ":" <> channel.id
          case fresh {
            [] -> Nil
            _ ->
              io.println(
                "processing discord messages from server: "
                <> state.guild.name
                <> " channel: "
                <> channel.name,
              )
          }
          list.each(fresh, fn(message) {
            let print = print_output(state.bot_token, channel.id, message.id, _)
            case event.from_message(message) {
              Ok(event) -> {
                let value = event.to_eyg(channel.name, event)
                list.each(state.triggers, fn(function) {
                  process.send(state.sessions, session.Trigger(function, value))
                })
              }
              Error(reason) -> io.println_error(reason)
            }
            case command.payload(message.data, state.bot_user) {
              Error(Nil) -> Nil
              Ok(payload) -> {
                process.send(
                  state.sessions,
                  session.Message(id: session_id, payload:, print:),
                )
              }
            }
          })
        }
      }
      State(
        ..state,
        conversations: dict.insert(
          state.conversations,
          channel.id,
          list.append(list.reverse(fresh), previous),
        ),
      )
    }
  }
}

fn print_output(
  token: String,
  channel: String,
  message: String,
  output: execute.Output,
) -> Nil {
  let #(text, prefix) = case output {
    execute.StandardOut(text) -> #(text, "")
    execute.StandardError(text) -> #(text, "stderr: ")
  }
  case string.trim(text) {
    "" -> Nil
    _ ->
      case client.create_message(token, channel, message, prefix <> text) {
        Ok(Nil) -> Nil
        Error(reason) -> report_failure(channel, reason)
      }
  }
}

fn report_failure(channel: String, reason: api.Failure) -> Nil {
  io.println_error("Discord " <> channel <> ": " <> string.inspect(reason))
  case reason {
    api.ApiFailure(operations.RateLimited(seconds)) -> {
      // Respect even global rate limits before requesting another channel.
      let milliseconds = float.ceiling(seconds *. 1000.0) |> float.truncate
      process.sleep(int.max(1, milliseconds))
    }
    _ -> Nil
  }
}
