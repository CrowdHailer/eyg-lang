//// What is happening in sessions now and is not recorded, such as a completion as it arrives
//// and messages sent to a chat while it is running.
//// It is kept in a process and lost when the service stops, the events of a session are what is kept.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result

/// The thinking and text of a completion so far.
pub type Arriving {
  Arriving(thinking: String, text: String)
}

/// Nothing is arriving.
pub const nothing = Arriving("", "")

pub opaque type Message {
  Show(session: String, arriving: Arriving)
  Clear(session: String)
  Get(session: String, reply: Subject(Arriving))
  Steer(session: String, message: String)
  Take(session: String, reply: Subject(List(String)))
}

pub type Live =
  Subject(Message)

type State {
  State(texts: Dict(String, Arriving), queued: Dict(String, List(String)))
}

pub fn start() -> Result(Live, actor.StartError) {
  actor.new(State(dict.new(), dict.new()))
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

fn handle(state: State, message) {
  case message {
    Show(session, text) ->
      actor.continue(
        State(..state, texts: dict.insert(state.texts, session, text)),
      )
    Clear(session) ->
      actor.continue(State(..state, texts: dict.delete(state.texts, session)))
    Get(session, reply) -> {
      process.send(
        reply,
        dict.get(state.texts, session) |> result.unwrap(nothing),
      )
      actor.continue(state)
    }
    // Messages are kept newest first.
    Steer(session, message) -> {
      let queued = dict.get(state.queued, session) |> result.unwrap([])
      let queued = dict.insert(state.queued, session, [message, ..queued])
      actor.continue(State(..state, queued:))
    }
    Take(session, reply) -> {
      let queued = dict.get(state.queued, session) |> result.unwrap([])
      process.send(reply, list.reverse(queued))
      actor.continue(State(..state, queued: dict.delete(state.queued, session)))
    }
  }
}

/// The completion the session is receiving.
pub fn show(live: Live, session: String, arriving: Arriving) -> Nil {
  process.send(live, Show(session, arriving))
}

pub fn clear(live: Live, session: String) -> Nil {
  process.send(live, Clear(session))
}

/// What the session has received so far, nothing if it is not receiving a completion.
pub fn arriving(live: Live, session: String) -> Arriving {
  process.call(live, 5000, Get(session, _))
}

/// Send a message to a chat while it is running, it is added to the chat after the tool calls that are running.
pub fn steer(live: Live, session: String, message: String) -> Nil {
  process.send(live, Steer(session, message))
}

/// The messages sent to the session that have not been added to its chat, oldest first.
/// They are removed, so each is taken once.
pub fn take(live: Live, session: String) -> List(String) {
  process.call(live, 5000, Take(session, _))
}
