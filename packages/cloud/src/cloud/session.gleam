//// A single actor executes queued code and owns each session's execution state.

import cloud/beam/execute
import eyg/hub/cache
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import ogre/origin

pub type Payload {
  Code(String)
}

pub type Message {
  Message(id: String, payload: Payload, print: fn(execute.Output) -> Nil)
}

type State {
  State(execute_state: execute.State, sessions: Dict(String, Nil))
}

pub fn start(hub: origin.Origin) -> actor.StartResult(Subject(Message)) {
  actor.new(State(execute.State(origin: hub, cache: cache.ready()), dict.new()))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  let Message(id, Code(code), print) = message
  let Nil = dict.get(state.sessions, id) |> result.unwrap(Nil)
  let #(outcome, execute_state) =
    execute.block(code, state.execute_state, print)
  case outcome {
    Ok(value) -> print(execute.StandardOut(value))
    Error(reason) -> print(execute.StandardError(reason))
  }
  actor.continue(State(
    execute_state:,
    sessions: dict.insert(state.sessions, id, Nil),
  ))
}
