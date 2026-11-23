//// What is happening in chats now and is not recorded, such as the text of a completion as it arrives.
//// It is kept in a process and lost when the service stops, the journal of a chat is what is kept.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result

pub opaque type Message {
  Show(chat: String, text: String)
  Clear(chat: String)
  Get(chat: String, reply: Subject(String))
}

pub type Live =
  Subject(Message)

pub fn start() -> Result(Live, actor.StartError) {
  actor.new(dict.new())
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

fn handle(texts: Dict(String, String), message) {
  case message {
    Show(chat, text) -> actor.continue(dict.insert(texts, chat, text))
    Clear(chat) -> actor.continue(dict.delete(texts, chat))
    Get(chat, reply) -> {
      process.send(reply, dict.get(texts, chat) |> result.unwrap(""))
      actor.continue(texts)
    }
  }
}

/// The text of the completion the chat is receiving.
pub fn show(live: Live, chat: String, text: String) -> Nil {
  process.send(live, Show(chat, text))
}

pub fn clear(live: Live, chat: String) -> Nil {
  process.send(live, Clear(chat))
}

/// The text the chat has received so far, empty if it is not receiving a completion.
pub fn text(live: Live, chat: String) -> String {
  process.call(live, 5000, Get(chat, _))
}
