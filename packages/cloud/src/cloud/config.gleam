//// Workspace configuration, written in EYG.
////
//// A workspace is configured by a `workspace.eyg` file that evaluates to a record:
////
//// - `llm` the `{provider, model}` the workspace's agents use, as in overlay.
//// - `readme` context given to every agent in the workspace.
//// - `channel` a function from `{platform, id, name}` to the channel's configuration.
////
//// The channel configuration is a record with:
////
//// - `channel_shell` the policy for every program run from the channel,
////   by people, by the channel's agent and by anything the channel starts.
//// - `readme` context given to the channel's agent.
//// - `handle` a pure function from the plugin's native input type to a list of work.
////
//// The configuration is trusted, it is evaluated with every effect available.

import cloud/beam/execute
import cloud/handler
import eyg/analysis/type_/binding
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import filepath
import gleam/dict
import gleam/option.{None, Some}
import gleam/result
import overlay/config as overlay
import overlay/llm/provider
import simplifile

pub type Workspace {
  Workspace(
    llm: provider.Llm,
    readme: String,
    channel: execute.Value,
    state: execute.State,
  )
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
  Channel(handle: execute.Value, shell: execute.Policy, readme: String)
}

/// Evaluate a workspace file, its relative imports are read from its directory.
pub fn load(file: String, state: execute.State) -> Result(Workspace, String) {
  use code <- result.try(
    simplifile.read(file)
    |> result.map_error(fn(reason) {
      "Failed to read " <> file <> ": " <> simplifile.describe_error(reason)
    }),
  )
  let state = execute.State(..state, root: Some(filepath.directory_name(file)))
  let host = execute.Host(post: fn(_) { Error("Configuration cannot post") })
  let #(execute.Run(result:, ..), state) =
    execute.run_configuration(code, execute.unrestricted(), host, state)
  case result {
    Ok(Some(value)) -> decode(value, state)
    Ok(None) -> Error(file <> " has no value")
    Error(reason) -> Error(file <> ": " <> reason)
  }
}

fn decode(value, state) {
  use llm <- result.try(field("llm", overlay.cast_llm, value))
  use readme <- result.try(optional_string("readme", value))
  use channel <- result.try(field("channel", Ok, value))
  Ok(Workspace(llm:, readme:, channel:, state:))
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
      Ok(Channel(handle:, shell:, readme:))
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
