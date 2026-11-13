//// Mutable workspace source and secrets, owned in memory.
//// Only plain data crosses this actor boundary; EYG is checked by its caller.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import gleam/string

pub type Snapshot {
  Snapshot(source: String, secrets: Dict(String, String))
}

pub type Message {
  Get(Subject(Snapshot))
  SetSource(String, Subject(Nil))
  SetSecret(String, String, Subject(Nil))
  DeleteSecret(String, Subject(Nil))
}

pub fn start(source, secrets) {
  actor.new(Snapshot(source, secrets))
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.map_error(string.inspect)
}

fn handle(state: Snapshot, message: Message) {
  case message {
    Get(reply) -> {
      process.send(reply, state)
      actor.continue(state)
    }
    SetSource(source, reply) -> {
      process.send(reply, Nil)
      actor.continue(Snapshot(..state, source:))
    }
    SetSecret(key, value, reply) -> {
      process.send(reply, Nil)
      actor.continue(
        Snapshot(..state, secrets: dict.insert(state.secrets, key, value)),
      )
    }
    DeleteSecret(key, reply) -> {
      process.send(reply, Nil)
      actor.continue(
        Snapshot(..state, secrets: dict.delete(state.secrets, key)),
      )
    }
  }
}
