//// Chats for tests, with the test server as the llm "test".

import cloud/apex/context.{type Context, Context}
import cloud/box
import cloud/chats/chat
import cloud/chats/event
import cloud/data/chats.{type Chat}
import cloud/helpers
import cloud/server
import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/option.{Some}
import howdy/testing as simulate

/// A chat with the server in a new box, made through the API.
pub fn chat(context: Context, server) -> #(Context, Chat) {
  let llms = dict.from_list([#("test", server.llm(server))])
  let context = Context(..context, llms:)
  let assert Ok(home) = box.create(context, Some(helpers.unique("home")))
  let response =
    simulate.request(http.Post, "/boxes/" <> home.id <> "/chats")
    |> simulate.json_body(json.object([#("llm", json.string("test"))]))
    |> helpers.dispatch(context)
  assert 201 == response.status
  let assert Ok(id) =
    json.parse(simulate.text(response), decode.at(["id"], decode.string))
  let assert Ok(made) = chat.find(context, id)
  #(context, made)
}

pub fn send(context: Context, chat: Chat, message: String) {
  chat.send(context, chat, message)
}

pub fn entries(context: Context, chat: Chat) -> List(event.Entry) {
  let assert Ok(entries) = chat.entries(context, chat.id)
  entries
}
