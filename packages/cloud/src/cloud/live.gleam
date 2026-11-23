//// What is happening in chats now and is not recorded, such as a completion as it arrives.
//// It is kept in a process and lost when the service stops, the journal of a chat is what is kept.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result

/// The thinking and text of a completion so far.
pub type Arriving {
  Arriving(thinking: String, text: String)
}

/// Nothing is arriving.
pub const nothing = Arriving("", "")

pub opaque type Message {
  Show(chat: String, arriving: Arriving)
  Clear(chat: String)
  Get(chat: String, reply: Subject(Arriving))
}

pub type Live =
  Subject(Message)

type State {
  State(texts: Dict(String, Arriving))
}

pub fn start() -> Result(Live, actor.StartError) {
  actor.new(State(dict.new()))
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

fn handle(state: State, message) {
  case message {
    Show(chat, text) ->
      actor.continue(State(texts: dict.insert(state.texts, chat, text)))
    Clear(chat) -> actor.continue(State(texts: dict.delete(state.texts, chat)))
    Get(chat, reply) -> {
      process.send(reply, dict.get(state.texts, chat) |> result.unwrap(nothing))
      actor.continue(state)
    }
  }
}

/// The completion the chat is receiving.
pub fn show(live: Live, chat: String, arriving: Arriving) -> Nil {
  process.send(live, Show(chat, arriving))
}

pub fn clear(live: Live, chat: String) -> Nil {
  process.send(live, Clear(chat))
}

/// What the chat has received so far, nothing if it is not receiving a completion.
pub fn arriving(live: Live, chat: String) -> Arriving {
  process.call(live, 5000, Get(chat, _))
}
