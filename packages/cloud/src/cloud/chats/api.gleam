//// A chat is a conversation with an llm about a box. Everything that happens is recorded in its journal.
//// The code of the llm's tool calls runs in shells.

import cloud/apex/api
import cloud/apex/context.{type Context}
import cloud/box
import cloud/box/controller.{reason, try} as _
import cloud/chats/chat
import cloud/chats/event
import cloud/data/chats.{type Chat}
import cloud/data/db
import gleam/dict
import gleam/dynamic/decode
import gleam/http/response
import gleam/json
import gleam/list
import gleam/string
import howdy/content
import howdy/controller
import oas/generator/utils
import overlay/llm/chat as llm
import overlay/llm/tool
import pog

/// A chat with the configured llm called `{"llm": name}`.
pub fn create(request: controller.Context, box, context: Context) {
  use body <- api.read_json(request)
  case decode.run(body, decode.at(["llm"], decode.string)) {
    Error(_) -> reason(400, "Expected an llm")
    Ok(llm) -> {
      use chat <- try(chat.start(context, box, llm))
      api.json(encode(chat), 201)
    }
  }
}

pub fn list(box, context: Context) {
  use rows <- try(run(chats.list(box), context))
  api.json(json.array(rows, encode), 200)
}

pub fn get(id, context: Context) {
  use chat <- try(chat.find(context, id))
  use entries <- try(chat.entries(context, id))
  json.object([
    #("id", json.string(chat.id)),
    #("box", json.string(chat.box)),
    #("llm", json.string(chat.llm)),
    #("messages", json.array(event.conversation(entries), encode_message)),
  ])
  |> api.json(200)
}

/// Send `{"message": message}` and wait for the reply.
pub fn send(request: controller.Context, id, context: Context) {
  use body <- api.read_json(request)
  case decode.run(body, decode.at(["message"], decode.string)) {
    Error(_) -> reason(400, "Expected a message")
    Ok(message) -> {
      use chat <- try(chat.find(context, id))
      use replied <- try(chat.send(context, chat, message))
      api.json(json.object([outcome(replied)]), 200)
    }
  }
}

/// Every entry of the journal as a line of JSON with the time it was recorded.
pub fn export(id, context: Context) {
  use history <- try(chat.history(context, id))
  history
  |> list.map(fn(entry) {
    let #(at, entry) = entry
    json.to_string(
      json.object([#("at", json.int(at)), #("entry", event.encode(entry))]),
    )
    <> "\n"
  })
  |> string.concat
  |> content.Text
  |> response.set_body(response.new(200), _)
  |> response.set_header("content-type", "application/x-ndjson")
}

/// The names of the llms a chat can be with.
pub fn llms(context: Context) {
  dict.keys(context.llms)
  |> list.sort(string.compare)
  |> json.array(json.string)
  |> api.json(200)
}

fn outcome(replied) {
  case replied {
    Ok(reply) -> #("reply", json.string(reply))
    Error(reason) -> #("error", json.string(reason))
  }
}

fn encode(chat: Chat) {
  json.object([
    #("id", json.string(chat.id)),
    #("box", json.string(chat.box)),
    #("llm", json.string(chat.llm)),
  ])
}

fn encode_message(message) {
  case message {
    llm.UserMessage(text, _) ->
      json.object([
        #("role", json.string("user")),
        #("content", json.string(text)),
      ])
    llm.AssistantMessage(_, text, calls) ->
      json.object([
        #("role", json.string("assistant")),
        #("content", json.string(text)),
        #(
          "tool_calls",
          json.array(calls, fn(call: tool.Call) {
            json.object([
              #("id", json.string(call.id)),
              #("name", json.string(call.function.name)),
              #("arguments", utils.fields_to_json(call.function.arguments)),
            ])
          }),
        ),
      ])
    llm.ToolResultMessage(id, text, _) ->
      json.object([
        #("role", json.string("tool")),
        #("tool_call_id", json.string(id)),
        #("content", json.string(text)),
      ])
  }
}

fn run(query, context: Context) {
  case db.execute(query, context.db) {
    Ok(pog.Returned(rows:, ..)) -> Ok(rows)
    Error(reason) -> Error(box.Failed(string.inspect(reason)))
  }
}
