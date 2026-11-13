//// A single actor executes queued code and owns each session's execution state.

import cloud/beam/execute
import eyg/hub/cache
import eyg/interpreter/simple_debug
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
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
  actor.new(State(
    execute.State(origin: hub, cache: cache.ready(), root: None),
    dict.new(),
  ))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  let Message(id, Code(code), print) = message
  let Nil = dict.get(state.sessions, id) |> result.unwrap(Nil)
  let host =
    execute.Host(post: fn(text) {
      print(execute.StandardOut(text))
      Ok(id)
    })
  let #(run, execute_state) =
    execute.run(code, [], execute.unrestricted(), host, state.execute_state)
  list.each(list.reverse(run.output), print)
  case run.result {
    Ok(Some(value)) -> print(execute.StandardOut(simple_debug.inspect(value)))
    Ok(None) -> Nil
    Error(reason) -> print(execute.StandardError(reason))
  }
  actor.continue(State(
    execute_state:,
    sessions: dict.insert(state.sessions, id, Nil),
  ))
}
