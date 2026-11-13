//// A single actor executes queued code and agent turns in each session.

import cloud/beam/execute
import cloud/beam/file_system
import cloud/overlay
import cloud/trigger
import eyg/hub/cache
import eyg/interpreter/state
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/otp/actor
import multiformats/cid/v1
import ogre/origin
import overlay/llm/chat
import overlay/llm/provider
import simplifile
import unixfs/mfs

pub type Payload {
  Code(String)
  UserPrompt(String)
}

pub type Message {
  Message(id: String, payload: Payload, print: fn(execute.Output) -> Nil)
  Trigger(function: trigger.Checked, value: state.Value(execute.Meta))
}

type State {
  State(
    execute_state: execute.State,
    policy: execute.Policy,
    blocks: Dict(v1.Cid, mfs.Entry),
    sessions: Dict(String, Session),
    // session is not a good name for overlay.Session
    // it is closer to config as it is constant over the session life time.
    agent_config: overlay.Session,
  )
}

pub type Session {
  Session(root: v1.Cid, history: chat.History)
}

pub fn start(
  hub: origin.Origin,
  llm: provider.Llm,
  secrets: Dict(String, String),
) -> actor.StartResult(Subject(Message)) {
  start_with_session(hub, overlay.setup(hub, llm), secrets)
}

pub fn start_with_session(
  hub: origin.Origin,
  agent_session: overlay.Session,
  secrets: Dict(String, String),
) -> actor.StartResult(Subject(Message)) {
  // policy.eyg could be moved to shared startup configuration later.
  let assert Ok(code) = simplifile.read("policy.eyg")
  let #(policy, execute_state) =
    execute.load_policy(
      code,
      execute.State(origin: hub, cache: cache.ready(), secrets:),
    )
  let assert Ok(policy) = policy
  actor.new(State(
    execute_state:,
    policy:,
    blocks: dict.new(),
    sessions: dict.new(),
    agent_config: agent_session,
  ))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    Trigger(function, value) -> {
      let #(outcome, execute_state, _) =
        execute.call(
          function,
          value,
          state.execute_state,
          // TODO triggers shouldn't need the same as an individual channel policy.
          state.policy,
          file_system.new(dict.new()),
          fn(_) { Nil },
        )
      case outcome {
        Ok(Nil) -> Nil
        Error(reason) -> io.println_error("Trigger failed: " <> reason)
      }
      actor.continue(State(..state, execute_state:))
    }
    Message(id, action, print) -> handle_session(state, id, action, print)
  }
}

fn handle_session(state: State, id, action, print) {
  let #(files, history) = case dict.get(state.sessions, id) {
    Ok(Session(root:, history:)) -> #(
      file_system.State(root, state.blocks),
      history,
    )
    Error(Nil) -> #(file_system.new(state.blocks), [])
  }
  let #(history, execute_state, files) = case action {
    Code(code) -> {
      let #(outcome, execute_state, files) =
        execute.block(code, state.execute_state, state.policy, files, print)
      case outcome {
        Ok(value) -> print(execute.StandardOut(value))
        Error(reason) -> print(execute.StandardError(reason))
      }
      #(history, execute_state, files)
    }
    UserPrompt(text) ->
      overlay.inner_loop(
        state.agent_config,
        state.execute_state,
        state.policy,
        [chat.UserMessage(text, []), ..history],
        files,
        print,
      )
  }
  actor.continue(
    State(
      ..state,
      execute_state:,
      blocks: files.blocks,
      sessions: dict.insert(state.sessions, id, Session(files.root, history)),
    ),
  )
}
