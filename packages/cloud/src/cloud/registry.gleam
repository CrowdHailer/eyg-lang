//// The workspaces and users of a cloud.
////
//// The registry starts every workspace in `cloud.eyg` and gives each the configuration API,
//// see `cloud/api`. It holds Gleam data only: names, files and subjects.

import cloud/artifacts
import cloud/beam/execute
import cloud/config
import cloud/secrets
import cloud/users.{type User}
import cloud/workspace
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string

pub type Handle {
  Handle(
    name: String,
    file: String,
    load: config.Loader,
    workspace: Subject(workspace.Message),
  )
}

pub type Message {
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
    data: String,
  )
}

/// Start each workspace of the cloud. `shells` are the names of the shells in `cloud.eyg`,
/// users are kept in the `data` directory.
pub fn start(
  entries: List(#(String, String)),
  shells: List(String),
  state: execute.State,
  artifacts: Subject(artifacts.Message),
  data: String,
) -> Result(Subject(Message), String) {
  use handles <- result.try(
    list.try_map(entries, fn(entry) {
      let #(name, file) = entry
      let directory = secrets.data_directory(file)
      let load = config.loader(file, state, secrets.get(directory, _))
      use workspace <- result.map(
        workspace.start(load, artifacts)
        |> result.map_error(fn(reason) { name <> ": " <> reason }),
      )
      Handle(name:, file:, load:, workspace:)
    }),
  )
  use users <- result.try(users.read(data))
  State(handles:, users:, shells:, data:)
  |> actor.new
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.map_error(string.inspect)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
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
        use Nil <- result.map(users.write(state.data, users))
        #(user, users)
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
          let written = users.write(state.data, users)
          process.send(reply, written)
          case written {
            Ok(Nil) -> actor.continue(State(..state, users:))
            Error(_) -> actor.continue(state)
          }
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
