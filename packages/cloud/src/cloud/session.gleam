//// A single actor executes queued code and agent turns in each session.

import cloud/beam/execute
import cloud/config
import cloud/file_system
import cloud/overlay
import cloud/trigger
import eyg/hub/cache
import eyg/interpreter/state
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/otp/actor
import gleam/result
import multiformats/cid/v1
import ogre/origin
import overlay/llm/chat
import overlay/llm/provider
import simplifile
import touch_grass/source

pub type Payload {
  Code(String)
  UserPrompt(String)
}

pub type Message {
  Message(id: String, payload: Payload, print: fn(execute.Output) -> Nil)
  Trigger(function: trigger.Checked, value: state.Value(source.Location))
}

type State {
  State(
    execute_state: execute.State,
    policy: execute.Policy,
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
  bucket: config.S3Bucket,
) -> actor.StartResult(Subject(Message)) {
  start_with_session(hub, overlay.setup(hub, llm), secrets, bucket)
}

pub fn start_with_session(
  hub: origin.Origin,
  agent_session: overlay.Session,
  secrets: Dict(String, String),
  bucket,
) -> actor.StartResult(Subject(Message)) {
  // policy.eyg could be moved to shared startup configuration later.
  let assert Ok(code) = simplifile.read("policy.eyg")

  let #(policy, execute_state) =
    execute.load_policy(
      code,
      source.Host("policy.eyg"),
      execute.State(
        origin: hub,
        cache: cache.ready(),
        secrets:,
        bucket:,
        pins: dict.new(),
      ),
      execute.template(),
    )
  let assert Ok(policy) = policy
  actor.new(State(
    execute_state:,
    policy:,
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
          empty(state.execute_state),
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
  let Session(root, history) =
    dict.get(state.sessions, id)
    |> result.lazy_unwrap(fn() { Session(empty(state.execute_state), []) })
  let #(history, execute_state, root) = case action {
    Code(code) -> {
      let #(outcome, execute_state, root, _) =
        execute.run(code, state.execute_state, state.policy, root, print)
      case outcome {
        Ok(value) -> print(execute.StandardOut(value))
        Error(reason) -> print(execute.StandardError(reason))
      }
      #(history, execute_state, root)
    }
    UserPrompt(text) ->
      overlay.inner_loop(
        state.agent_config,
        state.execute_state,
        state.policy,
        [chat.UserMessage(text, []), ..history],
        root,
        print,
      )
  }
  actor.continue(
    State(
      ..state,
      execute_state:,
      sessions: dict.insert(state.sessions, id, Session(root, history)),
    ),
  )
}

fn empty(state) {
  let assert Ok(root) = execute.files(file_system.empty(), state)
  root
}
