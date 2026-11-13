//// Channel plugin for the example chat app in `packages/example_chat`.
////
//// The plugin polls the chat's event log and reports posted messages and reactions.
//// It posts as `cloud`; the configured handler sees that native author ID.
//// See `guides/cloud/channel_plugins.md` for a walk through of this file.

import cloud/channel
import cloud/plugins/chat_input
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub const platform = "chat"

pub fn input_type() {
  chat_input.input_type()
}

const bot_id = "cloud"

pub type Config {
  Config(origin: String, poll_interval: Int)
}

/// Start polling the chat, `emit` is called with every event.
/// Events that happened before the plugin started are skipped.
pub fn start(
  config: Config,
  emit: fn(channel.Event) -> Nil,
) -> Result(channel.Outbound, String) {
  use events <- result.try(events(config, 0))
  let after = list.fold(events, 0, fn(_, event) { event.seq })
  process.spawn(fn() { poll(config, after, emit) })
  Ok(
    channel.Outbound(
      input_type: input_type(),
      post: fn(channel, reply, text) { post(config, channel, reply, text) },
      channel_name: fn(id) { channel_name(config, id) |> result.unwrap(id) },
      channels: fn() { channels(config) },
    ),
  )
}

fn poll(config: Config, after: Int, emit) -> Nil {
  let after = case events(config, after) {
    Ok(events) ->
      list.fold(events, after, fn(_, event) {
        emit(event.event)
        event.seq
      })
    Error(reason) -> {
      io.println_error("example chat: " <> reason)
      after
    }
  }
  process.sleep(config.poll_interval)
  poll(config, after, emit)
}

type Numbered {
  Numbered(seq: Int, event: channel.Event)
}

fn events(config: Config, after: Int) -> Result(List(Numbered), String) {
  use body <- result.try(get(
    config,
    "/api/events?after=" <> string.inspect(after),
  ))
  json.parse(body, decode.list(event_decoder()))
  |> result.map_error(string.inspect)
}

fn event_decoder() {
  use seq <- decode.field("seq", decode.int)
  use kind <- decode.field("type", decode.string)
  use message <- decode.field("message", message_decoder())
  case kind {
    "reacted" -> {
      use emoji <- decode.field("emoji", decode.string)
      use by <- decode.field("by", participant_decoder())
      decode.success(Numbered(
        seq,
        incoming(message, chat_input.reacted(message, by, emoji)),
      ))
    }
    _ ->
      decode.success(Numbered(
        seq,
        incoming(message, chat_input.posted(message)),
      ))
  }
}

fn message_decoder() {
  use id <- decode.field("id", decode.string)
  use channel_id <- decode.field("channel", decode.string)
  use thread <- decode.field("thread", decode.optional(decode.string))
  use author <- decode.field("author", participant_decoder())
  use text <- decode.field("text", decode.string)
  decode.success(chat_input.Message(
    id:,
    channel: channel_id,
    thread:,
    author:,
    text:,
  ))
}

fn participant_decoder() {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use bot <- decode.field("bot", decode.bool)
  decode.success(chat_input.Author(id:, name:, bot:))
}

fn incoming(message: chat_input.Message, value) {
  channel.Incoming(platform, message.channel, message.thread, value)
}

fn post(config: Config, channel: String, reply, text: String) {
  let body =
    json.object([
      #("channel", json.string(channel)),
      #("thread", json.nullable(reply, json.string)),
      #(
        "author",
        json.object([
          #("id", json.string(bot_id)),
          #("name", json.string("cloud")),
          #("bot", json.bool(True)),
        ]),
      ),
      #("text", json.string(text)),
    ])
  use response <- result.try(send(
    config,
    http.Post,
    "/api/messages",
    Some(body),
  ))
  json.parse(response, decode.field("id", decode.string, decode.success))
  |> result.map_error(string.inspect)
}

fn channel_name(config: Config, id: String) -> Result(String, String) {
  use channels <- result.try(channels(config))
  list.key_find(channels, id) |> result.replace_error("unknown channel " <> id)
}

fn channels(config: Config) -> Result(List(#(String, String)), String) {
  use body <- result.try(get(config, "/api/channels"))
  let decoder = {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    decode.success(#(id, name))
  }
  json.parse(body, decode.list(decoder)) |> result.map_error(string.inspect)
}

fn get(config, path) {
  send(config, http.Get, path, None)
}

fn send(config: Config, method, path, body) -> Result(String, String) {
  use request <- result.try(
    request.to(config.origin <> path)
    |> result.replace_error("invalid url " <> config.origin <> path),
  )
  let request = case body {
    Some(body) ->
      request
      |> request.set_header("content-type", "application/json")
      |> request.set_body(json.to_string(body))
    None -> request
  }
  case httpc.send(request.set_method(request, method)) {
    Ok(response) if response.status == 200 -> Ok(response.body)
    Ok(response) -> Error(response.body)
    Error(reason) -> Error(string.inspect(reason))
  }
}
