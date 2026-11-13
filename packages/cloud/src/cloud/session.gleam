//// A single actor executes queued code and owns each session's execution state.

import cloud/beam/execute
import cloud/beam/file_system
import eyg/hub/cache
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import multiformats/cid/v1
import ogre/origin
import unixfs/mfs

pub type Payload {
  Code(String)
}

pub type Message {
  Message(id: String, payload: Payload, print: fn(execute.Output) -> Nil)
}

type State {
  State(
    execute_state: execute.State,
    blocks: Dict(v1.Cid, mfs.Entry),
    sessions: Dict(String, v1.Cid),
  )
}

pub fn start(hub: origin.Origin) -> actor.StartResult(Subject(Message)) {
  actor.new(State(
    execute_state: execute.State(origin: hub, cache: cache.ready()),
    blocks: dict.new(),
    sessions: dict.new(),
  ))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  let Message(id, Code(code), print) = message
  let files = case dict.get(state.sessions, id) {
    Ok(root) -> file_system.State(root, state.blocks)
    Error(Nil) -> file_system.new(state.blocks)
  }
  let #(outcome, execute_state, files) =
    execute.block(code, state.execute_state, files, print)
  case outcome {
    Ok(value) -> print(execute.StandardOut(value))
    Error(reason) -> print(execute.StandardError(reason))
  }
  actor.continue(State(
    execute_state:,
    blocks: files.blocks,
    sessions: dict.insert(state.sessions, id, files.root),
  ))
}
