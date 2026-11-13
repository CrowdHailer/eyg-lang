//// One actor discovers guild channels and polls their histories serially.

import cloud/beam/execute
import cloud/channel as routing
import cloud/discord/api/client as api
import cloud/discord/api/operations
import cloud/discord/api/schema
import cloud/discord/client
import cloud/discord/command
import cloud/discord/events
import cloud/session
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/io
import gleam/json
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
    guild: schema.Guild,
    subject: Subject(Message),
    bot_user: String,
    conversations: Dict(String, List(schema.Message)),
    sessions: Subject(session.Message),
    hook: option.Option(fn(routing.Event) -> Nil),
    seen: Dict(String, events.Seen),
    names: Dict(String, String),
    started: Int,
  )
}

pub fn start(
  bot_token: String,
  guild: schema.Guild,
  bot_user: String,
  sessions: Subject(session.Message),
) -> actor.StartResult(Subject(Message)) {
  start_with_hook(bot_token, guild, bot_user, sessions, option.None)
}

pub fn start_with_hook(bot_token, guild, bot_user, sessions, hook) {
  let #(seconds, nanos) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
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
      hook,
      dict.new(),
      dict.new(),
      seconds * 1000 + nanos / 1_000_000,
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
    Ok(channels) -> {
      let names =
        list.fold(channels, state.names, fn(names, channel) {
          dict.insert(names, channel.id, channel.name)
        })
      let state = list.fold(channels, State(..state, names:), load_conversation)
      case state.hook {
        option.None -> state
        option.Some(_) ->
          case client.active_threads(state.bot_token, state.guild.id) {
            Error(reason) -> {
              report_failure("threads", reason)
              state
            }
            Ok(threads) ->
              list.fold(threads, state, fn(state, thread) {
                observe(
                  state,
                  thread.id,
                  thread.parent_id,
                  option.Some(thread.id),
                  [],
                  True,
                )
              })
          }
      }
    }
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
      case loaded, state.hook {
        False, _ -> {
          io.println(
            "Loaded "
            <> int.to_string(list.length(fresh))
            <> " Discord messages",
          )
        }
        True, option.Some(_) -> Nil
        True, option.None -> {
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
            // Install/server ID and name: state.guild.id and state.guild.name.
            // Conversation ID and name: channel.id and channel.name.
            // This is where a configured hook would fit in.
            case command.payload(message.data, state.bot_user) {
              Error(Nil) -> Nil
              Ok(payload) -> {
                process.send(
                  state.sessions,
                  session.Message(id: session_id, payload:, print: print_output(
                    state.bot_token,
                    channel.id,
                    message.id,
                    _,
                  )),
                )
              }
            }
          })
        }
      }
      let state =
        State(
          ..state,
          conversations: dict.insert(
            state.conversations,
            channel.id,
            list.append(list.reverse(fresh), previous),
          ),
        )
      let posts =
        list.filter_map(fresh, fn(message) {
          json.parse(json.to_string(message.data), schema.post_decoder())
        })
      observe(state, channel.id, channel.id, option.None, posts, loaded)
    }
  }
}

fn observe(state: State, id, parent, thread, fresh, loaded) {
  case state.hook {
    option.None -> state
    option.Some(emit) -> {
      case client.recent_messages(state.bot_token, id, 50) {
        Error(reason) -> {
          report_failure(id, reason)
          state
        }
        Ok(recent) -> {
          let previous =
            dict.get(state.seen, id) |> result.unwrap(events.unseen())
          let messages = list.append(fresh, list.reverse(recent))
          let #(posted, lookups, seen) =
            events.changes(
              parent,
              thread,
              previous,
              messages,
              state.bot_user,
              state.started,
            )
          case loaded {
            True -> list.each(posted, emit)
            False -> Nil
          }
          let seen =
            list.fold(lookups, seen, fn(seen, lookup) {
              case
                client.reactions(
                  state.bot_token,
                  id,
                  lookup.message.raw.id,
                  lookup.emoji,
                )
              {
                Error(reason) -> {
                  report_failure(id, reason)
                  seen
                }
                Ok(users) -> {
                  let #(posted, seen) =
                    events.reactions(
                      seen,
                      lookup.message,
                      lookup.emoji,
                      lookup.before,
                      users,
                      state.bot_user,
                    )
                  case loaded {
                    True -> list.each(posted, emit)
                    False -> Nil
                  }
                  seen
                }
              }
            })
          State(..state, seen: dict.insert(state.seen, id, seen))
        }
      }
    }
  }
}

/// Explicit thread posts used by configured programs. Main's ordinary replies
/// still use message references through print_output below.
pub fn post(token, channel, thread, text) {
  case thread {
    option.None -> client.post_message(token, channel, text)
    option.Some(thread) ->
      case client.post_message(token, thread, text) {
        Error(api.ApiFailure(operations.DiscordError(schema.ApiError(
          code: 10_003,
          ..,
        )))) -> {
          let name =
            client.get_message(token, channel, thread)
            |> result.map(fn(message) { events.thread_name(message.content) })
            |> result.unwrap("Conversation")
          use Nil <- result.try(client.start_thread(
            token,
            channel,
            thread,
            name,
          ))
          client.post_message(token, thread, text)
        }
        result -> result
      }
  }
  |> result.map_error(string.inspect)
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
