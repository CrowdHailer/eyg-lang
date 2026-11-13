//// A single actor executes queued code and agent turns in each session.

import cloud/beam/execute
import cloud/beam/file_system
import cloud/config
import cloud/files
import cloud/overlay
import cloud/session_store
import cloud/shell
import eyg/hub/cache
import filepath
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
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
    directory: String,
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
  Dispatch(
    id: String,
    setup: Option(Setup),
    action: Action,
    reply: Option(Reply),
  )
  WithFiles(
    directory: String,
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
    storage: Option(String),
  )
}

pub type Session {
  Session(root: v1.Cid, history: chat.History, pending: List(String))
}

pub fn start(hub: origin.Origin, llm: provider.Llm) {
  start_with_session(hub, overlay.setup(hub, llm))
}

pub fn start_with_session(hub: origin.Origin, agent_session: overlay.Session) {
  start_actor(hub, agent_session, None)
}

pub fn start_persistent(hub, llm, directory) {
  start_actor(hub, overlay.setup(hub, llm), Some(directory))
}

fn start_actor(hub, agent_session, storage) {
  let assert Ok(code) = simplifile.read("policy.eyg")
  let #(policy, execute_state) =
    execute.load_policy(code, execute.State(hub, cache.ready(), None, None))
  let assert Ok(policy) = policy
  actor.new(State(
    execute_state:,
    policy:,
    blocks: dict.new(),
    sessions: dict.new(),
    agent_config: agent_session,
    setups: dict.new(),
    storage:,
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
        use #(stored, execution) <- result.map(open(
          state,
          id,
          setup.directory,
          setup.seed,
        ))
        let host = case reply {
          None -> setup.host
          Some(post) -> execute.Host(..setup.host, post:)
        }
        let #(stored, execution) =
          perform(stored, Setup(..setup, host:), action, execution)
        save(
          setup.directory,
          setup.name,
          setup.channel.platform,
          setup.channel.id,
          setup.location,
          stored,
        )
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
    WithFiles(directory, id, seed, run) -> {
      case open(state, id, directory, seed) {
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
          save(directory, id, "web", "", "web shell", stored)
          actor.continue(retain(state, id, stored, execution))
        }
      }
    }
  }
}

fn basic_message(state: State, id, action, print) {
  let opened = case state.storage {
    Some(directory) ->
      open(state, id, session_store.directory(directory, id), None)
    None -> {
      let #(fs, stored) = case dict.get(state.sessions, id) {
        Ok(stored) -> #(file_system.State(stored.root, state.blocks), stored)
        Error(Nil) -> {
          let fs = file_system.new(state.blocks)
          #(fs, Session(fs.root, [], []))
        }
      }
      Ok(#(
        stored,
        execute.State(
          ..state.execute_state,
          files: Some(execute.SessionFiles(fs, fn(_) { Ok(Nil) })),
        ),
      ))
    }
  }
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
      case state.storage {
        Some(directory) ->
          save(session_store.directory(directory, id), id, "", "", "", stored)
        None -> Nil
      }
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

fn open(state: State, id, directory, seed) {
  let path = filepath.join(directory, "files.json")
  let opened = case dict.get(state.sessions, id) {
    Ok(stored) -> Ok(#(stored, file_system.State(stored.root, state.blocks)))
    Error(Nil) -> {
      use #(history, pending) <- result.try(read_history(directory))
      use fs <- result.map(files.load_snapshot(seed, path, state.blocks))
      #(Session(fs.root, history, pending), fs)
    }
  }
  use #(stored, fs) <- result.map(opened)
  #(
    stored,
    execute.State(
      ..state.execute_state,
      root: None,
      files: Some(execute.SessionFiles(fs, files.save_snapshot(path, _))),
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

fn save(directory, identity, platform, channel, location, next: Session) {
  let content =
    json.object([
      #("identity", json.string(identity)),
      #("platform", json.string(platform)),
      #("channel", json.string(channel)),
      #("location", json.string(location)),
      #("history", chat.history_to_json(next.history)),
      #("pending", json.array(next.pending, json.string)),
    ])
    |> json.to_string
  case session_store.write(filepath.join(directory, "session.json"), content) {
    Ok(_) -> Nil
    Error(reason) -> io.println_error(identity <> " saving session: " <> reason)
  }
}

fn read_history(directory) {
  case simplifile.read(filepath.join(directory, "session.json")) {
    Error(simplifile.Enoent) -> Ok(#([], []))
    Error(reason) -> Error(simplifile.describe_error(reason))
    Ok(content) -> {
      let decoder = {
        use history <- decode.field("history", chat.history_decoder())
        use pending <- decode.field("pending", decode.list(decode.string))
        decode.success(#(history, pending))
      }
      json.parse(content, decoder)
      |> result.replace_error("invalid session snapshot: " <> directory)
    }
  }
}
