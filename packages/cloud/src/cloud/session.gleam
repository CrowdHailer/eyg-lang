//// A single actor executes queued code and agent turns in each session.

import cloud/beam/execute
import cloud/beam/file_system
import cloud/config
import cloud/files
import cloud/overlay
import cloud/shell
import cloud/trigger
import eyg/hub/cache
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import multiformats/cid/v1
import ogre/origin
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/ollama
import simplifile
import unixfs/mfs

pub const max_history = 200

pub type Payload {
  Code(String)
  UserPrompt(String)
}

/// Channel services and trusted configuration are supplied with a command.
/// Evaluated EYG closures never cross the actor boundary.
pub type Setup {
  Setup(
    name: String,
    channel: config.ChannelInfo,
    location: String,
    load: config.Loader,
    complete: overlay.Completer,
    host: execute.Host,
    seed: Option(String),
  )
}

pub type Reply =
  fn(String) -> Result(String, String)

pub type Action {
  Input(String)
  Observe(String)
  Reset
  Run(fn(execute.Host, execute.State) -> #(Option(String), execute.State))
}

pub type Message {
  Message(id: String, payload: Payload, print: fn(execute.Output) -> Nil)
  Trigger(function: trigger.Checked, value: execute.Value)
  Dispatch(
    id: String,
    setup: Option(Setup),
    action: Action,
    reply: Option(Reply),
  )
  WithFiles(
    identity: String,
    seed: Option(String),
    run: fn(Result(execute.State, String)) -> #(String, execute.State),
  )
}

type State {
  State(
    execute_state: execute.State,
    policy: execute.Policy,
    blocks: Dict(v1.Cid, mfs.Entry),
    sessions: Dict(String, Session),
    agent_config: overlay.Session,
    setups: Dict(String, Setup),
  )
}

pub type Session {
  Session(root: v1.Cid, history: chat.History, pending: List(String))
}

pub fn start(hub: origin.Origin, llm: provider.Llm, secrets) {
  start_with_session(hub, overlay.setup(hub, llm), secrets)
}

pub fn start_with_session(
  hub: origin.Origin,
  agent_session: overlay.Session,
  secrets,
) {
  start_actor(hub, agent_session, secrets)
}

fn start_actor(hub, agent_session, secrets) {
  let assert Ok(code) = simplifile.read("policy.eyg")
  let #(policy, execute_state) =
    execute.load_policy(
      code,
      execute.State(hub, cache.ready(), None, None, secrets),
    )
  let assert Ok(policy) = policy
  actor.new(State(
    execute_state:,
    policy:,
    blocks: dict.new(),
    sessions: dict.new(),
    agent_config: agent_session,
    setups: dict.new(),
  ))
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Configured channels select their own model and hub when preparing a turn.
pub fn start_configured() -> Result(Subject(Message), String) {
  let assert Ok(hub) = origin.from_string_strict("https://eyg.run")
  start(
    hub,
    provider.Llm(provider.Ollama(ollama.local()), "devstral-small-2:24b"),
    dict.new(),
  )
  |> result.map(fn(started) { started.data })
  |> result.map_error(string.inspect)
}

pub fn send(executor, id, action) {
  process.send(executor, Dispatch(id, None, action, None))
}

pub fn submit(executor, id, setup, action, reply) {
  process.send(executor, Dispatch(id, Some(setup), action, reply))
}

fn handle_message(state: State, message: Message) {
  case message {
    Trigger(function, value) -> {
      let #(outcome, execute_state, _) =
        execute.call(
          function,
          value,
          state.execute_state,
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
    Message(id, action, print) -> {
      actor.continue(basic_message(state, id, action, print))
    }
    Dispatch(id, supplied, action, reply) -> {
      let state = case supplied {
        None -> state
        Some(setup) ->
          State(..state, setups: dict.insert(state.setups, id, setup))
      }
      let outcome = {
        use setup <- result.try(
          dict.get(state.setups, id)
          |> result.replace_error("unknown session " <> id),
        )
        use #(stored, execution) <- result.map(open(state, id, setup.seed))
        let host = case reply {
          None -> setup.host
          Some(post) -> execute.Host(..setup.host, post:)
        }
        let #(stored, execution) =
          perform(stored, Setup(..setup, host:), action, execution)
        retain(state, id, stored, execution)
      }
      case outcome {
        Error(reason) -> {
          io.println_error(reason)
          actor.continue(state)
        }
        Ok(state) -> actor.continue(state)
      }
    }
    WithFiles(id, seed, run) -> {
      case open(state, id, seed) {
        Error(reason) -> {
          let _ = run(Error(reason))
          actor.continue(state)
        }
        Ok(#(stored, execution)) -> {
          let #(report, execution) = run(Ok(execution))
          let stored =
            Session(
              ..stored,
              history: overlay.trim(
                [chat.UserMessage(report, []), ..stored.history],
                max_history,
              ),
            )
          actor.continue(retain(state, id, stored, execution))
        }
      }
    }
  }
}

fn basic_message(state: State, id, action, print) {
  let opened = open(state, id, None)
  case opened {
    Error(reason) -> {
      print(execute.StandardError(reason))
      state
    }
    Ok(#(stored, execution)) -> {
      let assert Some(files) = execution.files
      let #(history, execution, fs) = case action {
        Code(code) -> {
          let #(outcome, execution, fs) =
            execute.block(code, execution, state.policy, files.state, print)
          case outcome {
            Ok(value) -> print(execute.StandardOut(value))
            Error(reason) -> print(execute.StandardError(reason))
          }
          #(stored.history, execution, fs)
        }
        UserPrompt(text) ->
          overlay.inner_loop(
            state.agent_config,
            execution,
            state.policy,
            [chat.UserMessage(text, []), ..stored.history],
            files.state,
            print,
          )
      }
      let stored =
        Session(fs.root, overlay.trim(history, max_history), stored.pending)
      State(
        ..state,
        execute_state: execute.State(..execution, files: None),
        blocks: fs.blocks,
        sessions: dict.insert(state.sessions, id, stored),
      )
    }
  }
}

fn retain(state: State, id, stored: Session, execution: execute.State) {
  let assert Some(files) = execution.files
  State(
    ..state,
    execute_state: execute.State(..execution, files: None),
    blocks: files.state.blocks,
    sessions: dict.insert(
      state.sessions,
      id,
      Session(..stored, root: files.state.root),
    ),
  )
}

fn open(state: State, id, seed) {
  let opened = case dict.get(state.sessions, id) {
    Ok(stored) -> Ok(#(stored, file_system.State(stored.root, state.blocks)))
    Error(Nil) -> {
      use fs <- result.map(files.seed(seed, state.blocks))
      #(Session(fs.root, [], []), fs)
    }
  }
  use #(stored, fs) <- result.map(opened)
  #(
    stored,
    execute.State(
      ..state.execute_state,
      root: None,
      files: Some(execute.SessionFiles(fs)),
    ),
  )
}

fn perform(
  stored: Session,
  setup: Setup,
  action: Action,
  execution: execute.State,
) {
  let assert Some(files) = execution.files
  let host =
    execute.Host(..setup.host, files: execute.session_files(files.state))
  case action {
    Reset -> #(Session(..stored, history: [], pending: []), execution)
    Observe(text) -> #(
      Session(..stored, pending: [text, ..stored.pending]),
      execution,
    )
    Run(run) -> {
      let #(report, execution) = run(host, execution)
      let stored = case report {
        None -> stored
        Some(text) -> Session(..stored, pending: [text, ..stored.pending])
      }
      #(stored, execution)
    }
    Input(text) -> {
      let text = [text, ..stored.pending] |> list.reverse |> string.join("\n\n")
      case
        shell.prepare(
          setup.load,
          setup.channel,
          host,
          setup.location,
          setup.complete,
        )
      {
        Error(reason) -> {
          let _ = host.post(reason)
          #(
            Session(
              ..stored,
              history: [chat.UserMessage(text, []), ..stored.history],
              pending: [],
            ),
            execution,
          )
        }
        Ok(shell) -> {
          let execution = execute.State(..shell.state, files: execution.files)
          let #(history, execution) =
            shell.turn(shell, stored.history, text, execution, fn(output) {
              let _ = host.post(execute.output_text(output))
              Nil
            })
          #(
            Session(
              ..stored,
              history: overlay.trim(history, max_history),
              pending: [],
            ),
            execution,
          )
        }
      }
    }
  }
}
