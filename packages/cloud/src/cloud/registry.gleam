//// The workspaces and users of a cloud.
////
//// The registry starts every workspace in `cloud.eyg` and gives each the configuration API,
//// see `cloud/api`. It holds Gleam data only: names, files and subjects.

import cloud/artifacts
import cloud/beam/execute
import cloud/config
import cloud/configuration
import cloud/overlay as agent
import cloud/session
import cloud/users.{type User}
import cloud/workspace
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import simplifile

pub type Handle {
  Handle(
    name: String,
    file: String,
    load: config.Loader,
    settings: Subject(configuration.Message),
    workspace: Subject(workspace.Message),
  )
}

pub type Message {
  Executor(reply: Subject(Subject(session.Message)))
  Workspaces(reply: Subject(List(Handle)))
  Users(reply: Subject(List(User)))
  Shells(reply: Subject(List(String)))
  SignIn(name: String, reply: Subject(Result(User, String)))
  UserByToken(token: String, reply: Subject(Result(User, Nil)))
  SetUserShell(user: String, shell: String, reply: Subject(Result(Nil, String)))
}

type State {
  State(
    handles: List(Handle),
    users: List(User),
    shells: List(String),
    executor: Subject(session.Message),
  )
}

/// Start each workspace of the cloud. `shells` are the names of the shells in `cloud.eyg`,
/// users and workspace settings are held in memory.
pub fn start(
  entries: List(#(String, String)),
  shells: List(String),
  state: execute.State,
  artifacts: Subject(artifacts.Message),
) -> Result(Subject(Message), String) {
  use executor <- result.try(session.start_configured())
  use handles <- result.try(
    list.try_map(entries, fn(entry) {
      let #(name, file) = entry
      use source <- result.try(
        simplifile.read(file) |> result.map_error(simplifile.describe_error),
      )
      use settings <- result.try(configuration.start(source, state.secrets))
      let load = fn() {
        let snapshot = process.call(settings, 5000, configuration.Get)
        config.load_source(file, snapshot.source, state, fn(key) {
          dict.get(snapshot.secrets, key)
          |> result.replace_error("no secret named " <> key)
        })
      }
      use workspace <- result.map(
        workspace.start_on(load, artifacts, agent.complete, executor, name)
        |> result.map_error(fn(reason) { name <> ": " <> reason }),
      )
      Handle(name:, file:, load:, settings:, workspace:)
    }),
  )
  State(handles:, users: [], shells:, executor:)
  |> actor.new
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.map_error(string.inspect)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Executor(reply:) -> {
      process.send(reply, state.executor)
      actor.continue(state)
    }
    Workspaces(reply:) -> {
      process.send(reply, state.handles)
      actor.continue(state)
    }
    Users(reply:) -> {
      process.send(reply, state.users)
      actor.continue(state)
    }
    Shells(reply:) -> {
      process.send(reply, state.shells)
      actor.continue(state)
    }
    SignIn(name:, reply:) -> {
      let shell = list.first(state.shells) |> result.unwrap("")
      let added = {
        use #(user, users) <- result.try(users.add(
          state.users,
          string.trim(name),
          token(),
          shell,
        ))
        Ok(#(user, users))
      }
      case added {
        Ok(#(user, users)) -> {
          process.send(reply, Ok(user))
          actor.continue(State(..state, users:))
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(state)
        }
      }
    }
    UserByToken(token:, reply:) -> {
      process.send(reply, users.by_token(state.users, token))
      actor.continue(state)
    }
    SetUserShell(user: name, shell:, reply:) -> {
      let known = list.any(state.users, fn(u) { u.name == name })
      case known, list.contains(state.shells, shell) {
        False, _ -> {
          process.send(reply, Error("no user named " <> name))
          actor.continue(state)
        }
        _, False -> {
          process.send(reply, Error("no shell named " <> shell))
          actor.continue(state)
        }
        True, True -> {
          let users =
            list.map(state.users, fn(u) {
              case u.name == name {
                True -> users.User(..u, shell:)
                False -> u
              }
            })
          process.send(reply, Ok(Nil))
          actor.continue(State(..state, users:))
        }
      }
    }
  }
}

fn token() {
  crypto.strong_random_bytes(18) |> bit_array.base64_url_encode(False)
}

pub fn workspace(
  registry: Subject(Message),
  name: String,
) -> Result(Handle, String) {
  process.call(registry, 5000, Workspaces)
  |> list.find(fn(h) { h.name == name })
  |> result.replace_error("no workspace named " <> name)
}
