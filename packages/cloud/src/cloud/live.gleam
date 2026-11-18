//// What is happening in sessions now and is not recorded, such as the text of a completion as it arrives.
//// It is kept in a process and lost when the service stops, the events of a session are what is kept.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result

pub opaque type Message {
  Show(session: String, text: String)
  Clear(session: String)
  Get(session: String, reply: Subject(String))
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
    Show(session, text) -> actor.continue(dict.insert(texts, session, text))
    Clear(session) -> actor.continue(dict.delete(texts, session))
    Get(session, reply) -> {
      process.send(reply, dict.get(texts, session) |> result.unwrap(""))
      actor.continue(texts)
    }
  }
}

/// The text of the completion the session is receiving.
pub fn show(live: Live, session: String, text: String) -> Nil {
  process.send(live, Show(session, text))
}

pub fn clear(live: Live, session: String) -> Nil {
  process.send(live, Clear(session))
}

/// The text the session has received so far, empty if it is not receiving a completion.
pub fn text(live: Live, session: String) -> String {
  process.call(live, 5000, Get(session, _))
}
