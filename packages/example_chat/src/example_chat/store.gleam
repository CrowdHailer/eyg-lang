//// The chat's state, held in one actor.
////
//// Every change is recorded as an event with a sequence number,
//// clients poll for the events after the last one they have seen.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/result

pub type Channel {
  Channel(id: String, name: String)
}

pub type Author {
  Author(id: String, name: String, bot: Bool)
}

pub type Reaction {
  Reaction(emoji: String, by: List(String))
}

pub type Message {
  Message(
    id: String,
    channel: String,
    thread: Option(String),
    author: Author,
    text: String,
    reactions: List(Reaction),
  )
}

pub type Event {
  Posted(seq: Int, message: Message)
  Reacted(seq: Int, message: Message, emoji: String, by: Author)
}

pub type Request {
  Channels(reply: Subject(List(Channel)))
  CreateChannel(name: String, reply: Subject(Channel))
  Messages(channel: String, reply: Subject(List(Message)))
  Post(
    channel: String,
    thread: Option(String),
    author: Author,
    text: String,
    reply: Subject(Result(Message, String)),
  )
  React(
    message: String,
    emoji: String,
    by: Author,
    reply: Subject(Result(Message, String)),
  )
  /// Events with a sequence number greater than `after`, oldest first.
  Events(after: Int, reply: Subject(List(Event)))
}

type State {
  State(
    channels: List(Channel),
    messages: Dict(String, Message),
    order: List(String),
    events: List(Event),
    seq: Int,
  )
}

pub fn start(channels: List(String)) -> Result(Subject(Request), String) {
  let state =
    State(channels: [], messages: dict.new(), order: [], events: [], seq: 0)
  let state =
    list.fold(channels, state, fn(state, name) { create(state, name).0 })
  actor.new(state)
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.replace_error("failed to start store")
}

fn handle(state: State, request: Request) -> actor.Next(State, Request) {
  case request {
    Channels(reply) -> {
      process.send(reply, list.reverse(state.channels))
      actor.continue(state)
    }
    CreateChannel(name, reply) -> {
      let #(state, channel) = create(state, name)
      process.send(reply, channel)
      actor.continue(state)
    }
    Messages(channel, reply) -> {
      state.order
      |> list.reverse
      |> list.filter_map(dict.get(state.messages, _))
      |> list.filter(fn(message) { message.channel == channel })
      |> process.send(reply, _)
      actor.continue(state)
    }
    Post(channel:, thread:, author:, text:, reply:) -> {
      case post(state, channel, thread, author, text) {
        Ok(#(state, message)) -> {
          process.send(reply, Ok(message))
          actor.continue(state)
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(state)
        }
      }
    }
    React(message:, emoji:, by:, reply:) ->
      case dict.get(state.messages, message) {
        Ok(found) -> {
          let found =
            Message(..found, reactions: add(found.reactions, emoji, by))
          let seq = state.seq + 1
          let state =
            State(
              ..state,
              messages: dict.insert(state.messages, found.id, found),
              events: [Reacted(seq, found, emoji, by), ..state.events],
              seq:,
            )
          process.send(reply, Ok(found))
          actor.continue(state)
        }
        Error(Nil) -> {
          process.send(reply, Error("unknown message " <> message))
          actor.continue(state)
        }
      }
    Events(after, reply) -> {
      state.events
      |> list.take_while(fn(event) { event.seq > after })
      |> list.reverse
      |> process.send(reply, _)
      actor.continue(state)
    }
  }
}

fn create(state: State, name) {
  let id = "C" <> int.to_string(list.length(state.channels) + 1)
  let channel = Channel(id:, name:)
  #(State(..state, channels: [channel, ..state.channels]), channel)
}

fn post(state: State, channel, thread, author, text) {
  use _ <- result.try(
    list.find(state.channels, fn(c) { c.id == channel })
    |> result.replace_error("unknown channel " <> channel),
  )
  let seq = state.seq + 1
  let id = "m" <> int.to_string(seq)
  // A reply to a reply belongs to the same thread.
  let thread =
    option.map(thread, fn(thread) {
      case dict.get(state.messages, thread) {
        Ok(Message(thread: option.Some(root), ..)) -> root
        _ -> thread
      }
    })
  let message = Message(id:, channel:, thread:, author:, text:, reactions: [])
  let state =
    State(
      ..state,
      messages: dict.insert(state.messages, id, message),
      order: [id, ..state.order],
      events: [Posted(seq, message), ..state.events],
      seq:,
    )
  Ok(#(state, message))
}

fn add(reactions: List(Reaction), emoji, by: Author) {
  case list.find(reactions, fn(r) { r.emoji == emoji }) {
    Ok(Reaction(by: names, ..)) ->
      list.map(reactions, fn(r) {
        case r.emoji == emoji && !list.contains(names, by.name) {
          True -> Reaction(emoji, list.append(names, [by.name]))
          False -> r
        }
      })
    Error(Nil) -> list.append(reactions, [Reaction(emoji, [by.name])])
  }
}

pub fn call(store: Subject(Request), make) {
  process.call(store, 5000, make)
}
