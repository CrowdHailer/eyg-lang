//// The chat HTTP API and Lustre live view, served by howdy.
//// Platform clients retain the same JSON routes and event cursor contract.

import example_chat/store.{type Message}
import example_chat/view
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import howdy
import howdy/controller
import howdy/ui/live
import howdy/ui/page
import lustre/element/html

pub fn app(store: Subject(store.Request), styles: String) -> howdy.App {
  let routes =
    controller.new("/")
    |> controller.get("/", fn(ctx) {
      let route = case ctx.request.query {
        Some(query) -> "/live/chat?" <> query
        None -> "/live/chat"
      }
      page.new("Example chat")
      |> page.live
      |> page.head([html.style([], styles)])
      |> page.body([live.mount(route)])
      |> page.respond(ctx)
    })
    |> controller.get("/live/chat", fn(ctx) {
      let args =
        view.Args(
          store:,
          name: query(ctx, "name") |> result.unwrap("alice"),
          channel: query(ctx, "channel") |> result.unwrap(""),
        )
      live.serve(ctx, view.app(), with: args)
    })
    |> controller.get("/api/channels", fn(ctx) {
      store.call(store, store.Channels)
      |> json.array(channel_json)
      |> controller.json(ctx, _)
    })
    |> controller.post("/api/channels", fn(ctx) {
      use name <- body(ctx, decode.field("name", decode.string, decode.success))
      store.call(store, store.CreateChannel(name, _))
      |> channel_json
      |> controller.json(ctx, _)
    })
    |> controller.get("/api/messages", fn(ctx) {
      let channel = query(ctx, "channel") |> result.unwrap("")
      store.call(store, store.Messages(channel, _))
      |> json.array(message_json)
      |> controller.json(ctx, _)
    })
    |> controller.post("/api/messages", fn(ctx) {
      use #(channel, thread, author, text) <- body(ctx, {
        use channel <- decode.field("channel", decode.string)
        use thread <- decode.field("thread", decode.optional(decode.string))
        use author <- decode.field("author", author_decoder())
        use text <- decode.field("text", decode.string)
        decode.success(#(channel, thread, author, text))
      })
      store.call(store, store.Post(channel, thread, author, text, _))
      |> result_reply(ctx, _)
    })
    |> controller.post("/api/reactions", fn(ctx) {
      use #(message, emoji, author) <- body(ctx, {
        use message <- decode.field("message", decode.string)
        use emoji <- decode.field("emoji", decode.string)
        use author <- decode.field("author", author_decoder())
        decode.success(#(message, emoji, author))
      })
      store.call(store, store.React(message, emoji, author, _))
      |> result_reply(ctx, _)
    })
    |> controller.get("/api/events", fn(ctx) {
      let after =
        query(ctx, "after") |> result.try(int.parse) |> result.unwrap(0)
      store.call(store, store.Events(after, _))
      |> json.array(event_json)
      |> controller.json(ctx, _)
    })
  howdy.new() |> howdy.controller(routes)
}

fn query(ctx: controller.Context, key) {
  request.get_query(ctx.request) |> result.unwrap([]) |> list.key_find(key)
}

fn body(ctx, decoder, then) {
  case controller.read_body(ctx, limit: 1_000_000) {
    Ok(bytes) ->
      case json.parse_bits(bytes, decoder) {
        Ok(value) -> then(value)
        Error(_) -> status(ctx, 400, "invalid request body")
      }
    Error(_) -> status(ctx, 400, "unreadable request body")
  }
}

fn author_decoder() {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use bot <- decode.field("bot", decode.bool)
  decode.success(store.Author(id:, name:, bot:))
}

pub fn channel_json(channel: store.Channel) {
  json.object([
    #("id", json.string(channel.id)),
    #("name", json.string(channel.name)),
  ])
}

pub fn message_json(message: Message) {
  let store.Message(id:, channel:, thread:, author:, text:, reactions:) =
    message
  json.object([
    #("id", json.string(id)),
    #("channel", json.string(channel)),
    #("thread", json.nullable(thread, json.string)),
    #("author", author_json(author)),
    #("text", json.string(text)),
    #(
      "reactions",
      json.array(reactions, fn(reaction) {
        json.object([
          #("emoji", json.string(reaction.emoji)),
          #("by", json.array(reaction.by, json.string)),
        ])
      }),
    ),
  ])
}

fn author_json(author: store.Author) {
  json.object([
    #("id", json.string(author.id)),
    #("name", json.string(author.name)),
    #("bot", json.bool(author.bot)),
  ])
}

fn event_json(event: store.Event) {
  case event {
    store.Posted(seq:, message:) ->
      json.object([
        #("seq", json.int(seq)),
        #("type", json.string("posted")),
        #("message", message_json(message)),
      ])
    store.Reacted(seq:, message:, emoji:, by:) ->
      json.object([
        #("seq", json.int(seq)),
        #("type", json.string("reacted")),
        #("message", message_json(message)),
        #("emoji", json.string(emoji)),
        #("by", author_json(by)),
      ])
  }
}

fn result_reply(ctx, result) {
  case result {
    Ok(message) -> controller.json(ctx, message_json(message))
    Error(reason) -> status(ctx, 400, reason)
  }
}

fn status(ctx, code, text) {
  let response = controller.text(ctx, text)
  response.Response(..response, status: code)
}
