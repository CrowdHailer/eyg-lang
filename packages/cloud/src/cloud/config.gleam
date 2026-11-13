//// Workspace configuration, written in EYG.
////
//// A workspace is configured by a `workspace.eyg` file that evaluates to a record:
////
//// - `llm` the `{provider, model}` the workspace's agents use, as in overlay.
//// - `readme` context given to every agent in the workspace.
//// - `channel` a function from `{platform, id, name}` to the channel's configuration.
//// - `files` optional, a directory relative to the workspace file that the
////   workspace's shared file system starts with.
//// - `crons` optional, a list of `{name, schedule, channel, message}` records,
////   the message is sent to the named channel's session on the cron schedule, see `cloud/cron`.
////
//// The channel configuration is a record with:
////
//// - `channel_shell` the policy for every program run from the channel,
////   by people, by the channel's agent and by anything the channel starts.
//// - `readme` optional, context given to the channel's agent.
//// - `triggers` optional, a list of `{name, pattern, script}` triggers installed in the channel, see `cloud/trigger`.
//// - `handle` a pure function from the plugin's native input type to a list of work.
////
//// The configuration is trusted, it is evaluated with every effect available
//// and can read the workspace's secrets with the `Secret` effect.

import cloud/beam/execute
import cloud/handler
import cloud/trigger
import eyg/analysis/type_/binding
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import filepath
import gleam/dict
import gleam/option.{type Option, None, Some}
import gleam/result
import overlay/config as overlay
import overlay/llm/provider
import simplifile

pub type Workspace {
  Workspace(
    llm: provider.Llm,
    readme: String,
    channel: execute.Value,
    /// The host directory the workspace's file system starts with.
    files: Option(String),
    crons: List(Cron),
    state: execute.State,
  )
}

/// A message sent to a channel's session on a schedule.
pub type Cron {
  Cron(name: String, schedule: String, channel: String, message: String)
}

/// Evaluates the workspace configuration.
/// Configuration contains EYG values that must not be sent between processes,
/// each process that needs the configuration evaluates it, see `notes/cloud-process-boundaries.md`.
pub type Loader =
  fn() -> Result(Workspace, String)

pub fn loader(
  file: String,
  state: execute.State,
  secret: fn(String) -> Result(String, String),
) -> Loader {
  fn() { load(file, state, secret) }
}

/// The identity of a channel passed to the workspace's `channel` function.
pub type ChannelInfo {
  ChannelInfo(
    platform: String,
    id: String,
    name: String,
    input_type: binding.Mono,
  )
}

pub type Channel {
  Channel(
    handle: execute.Value,
    shell: execute.Policy,
    readme: String,
    triggers: List(trigger.Trigger),
  )
}

/// Evaluate a workspace file, its relative imports are read from its directory.
/// The `Secret` effect reads from `secret`.
pub fn load(
  file: String,
  state: execute.State,
  secret: fn(String) -> Result(String, String),
) -> Result(Workspace, String) {
  use code <- result.try(
    simplifile.read(file)
    |> result.map_error(fn(reason) {
      "Failed to read " <> file <> ": " <> simplifile.describe_error(reason)
    }),
  )
  let state = execute.State(..state, root: Some(filepath.directory_name(file)))
  let host = execute.configuration_host(secret)
  let #(execute.Run(result:, ..), state) =
    execute.run_configuration(code, execute.configuration(), host, state)
  case result {
    Ok(Some(value)) -> decode(value, filepath.directory_name(file), state)
    Ok(None) -> Error(file <> " has no value")
    Error(reason) -> Error(file <> ": " <> reason)
  }
}

fn decode(value, directory, state) {
  use llm <- result.try(field("llm", overlay.cast_llm, value))
  use readme <- result.try(optional_string("readme", value))
  use channel <- result.try(field("channel", Ok, value))
  use files <- result.try(case cast.field("files", Ok, value) {
    Ok(_) ->
      field("files", cast.as_string, value)
      |> result.map(fn(path) { Some(filepath.join(directory, path)) })
    Error(_) -> Ok(None)
  })
  use crons <- result.try(case cast.field("crons", Ok, value) {
    Ok(_) -> field("crons", cast.as_list_of(_, decode_cron), value)
    Error(_) -> Ok([])
  })
  Ok(Workspace(llm:, readme:, channel:, files:, crons:, state:))
}

fn decode_cron(value) {
  use name <- result.try(cast.field("name", cast.as_string, value))
  use schedule <- result.try(cast.field("schedule", cast.as_string, value))
  use channel <- result.try(cast.field("channel", cast.as_string, value))
  use message <- result.try(cast.field("message", cast.as_string, value))
  Ok(Cron(name:, schedule:, channel:, message:))
}

/// Call the workspace's `channel` function for one channel.
pub fn channel(
  workspace: Workspace,
  info: ChannelInfo,
) -> Result(Channel, String) {
  let ChannelInfo(platform:, id:, name:, ..) = info
  let argument =
    v.Record(
      dict.from_list([
        #("platform", v.String(platform)),
        #("id", v.String(id)),
        #("name", v.String(name)),
      ]),
    )
  let #(returned, _state) =
    execute.pure_loop(
      expression.call(workspace.channel, [#(argument, #(0, 0))]),
      workspace.state,
    )
  case returned {
    Ok(value) -> {
      use handle <- result.try(field("handle", Ok, value))
      use handle <- result.try(
        handler.check(handle, info.input_type, workspace.state)
        |> result.map_error(fn(reason) { "handle: " <> reason }),
      )
      use shell <- result.try(field("channel_shell", Ok, value))
      use shell <- result.try(
        execute.decode_policy(shell, workspace.state)
        |> result.map_error(fn(reason) { "channel_shell: " <> reason }),
      )
      use readme <- result.try(optional_string("readme", value))
      use triggers <- result.try(case cast.field("triggers", Ok, value) {
        Ok(_) -> field("triggers", cast.as_list_of(_, trigger.decode), value)
        Error(_) -> Ok([])
      })
      Ok(Channel(handle:, shell:, readme:, triggers:))
    }
    Error(#(reason, _, _, _)) ->
      Error("channel " <> name <> ": " <> simple_debug.describe(reason))
  }
}

fn field(name, decoder, value) {
  cast.field(name, decoder, value)
  |> result.map_error(fn(reason) {
    name <> ": " <> simple_debug.describe(reason)
  })
}

fn optional_string(name, value) {
  case cast.field(name, Ok, value) {
    Ok(_) -> field(name, cast.as_string, value)
    Error(_) -> Ok("")
  }
}
