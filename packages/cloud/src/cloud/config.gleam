//// Workspace configuration, written in EYG.
////
//// A workspace is configured by a `workspace.eyg` file that evaluates to a record:
////
//// - `llm` the `{provider, model}` the workspace's agents use, as in overlay.
//// - `readme` context given to every agent in the workspace.
//// - `channel` a function from `{platform, installation, id, name}` to the channel's configuration.
//// - `files` optional, a directory relative to the workspace file that the
////   private session file systems are seeded from once.
//// - `crons` optional, a list of `{name, schedule, channel, message}` records,
////   the message is sent to the named channel's session on the cron schedule, see `cloud/schedule`.
//// - `connections` optional, a list of `{name, source}` chat connections,
////   see `cloud/connection`.
////
//// The channel configuration is a record with:
////
//// - `channel_shell` the policy for every program run from the channel,
////   by people, by the channel's agent and by anything the channel starts.
//// - `readme` optional, context given to the channel's agent.
//// - `triggers` optional, a list of `{name, pattern, script}` triggers installed in the channel, see `cloud/trigger`.
//// - `on_input` a pure function from the plugin's native input type to a list of work.
//// - `llm` optional, the model for the channel's agents instead of the workspace's.
////
//// The configuration is trusted, it is evaluated with every effect available
//// and can read the workspace's secrets with the `Secret` effect.

import cloud/beam/execute
import cloud/channel
import cloud/check
import cloud/connection
import cloud/handler
import cloud/tracing
import cloud/trigger/configured as trigger
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import filepath
import gleam/dict
import gleam/list
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
    channel_type: binding.Poly,
    /// The host directory the workspace's file system starts with.
    files: Option(String),
    crons: List(Cron),
    connections: List(connection.Connection),
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
  let state = execute.State(..state, root: Some(filepath.directory_name(file)))
  let prepared = {
    use code <- result.try(
      simplifile.read(file) |> result.map_error(simplifile.describe_error),
    )
    use plan <- result.map(execute.prepare_configuration(
      code,
      state,
      check_workspace,
    ))
    #(code, plan)
  }
  fn() {
    case prepared {
      Ok(#(code, #(source, type_, state, imports))) -> {
        case
          simplifile.read(file) == Ok(code)
          && list.all(imports, fn(entry) {
            simplifile.read_bits(entry.0) == Ok(entry.1)
          })
        {
          True -> evaluate(file, source, type_, state, secret)
          False -> load(file, state, secret)
        }
      }
      Error(_) -> load(file, state, secret)
    }
  }
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
    /// The model for the channel's agents, the workspace's unless the channel sets one.
    llm: provider.Llm,
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
  load_source(file, code, state, secret)
}

/// Evaluate the source of a workspace file, for checking a change before it is saved.
pub fn load_source(
  file: String,
  code: String,
  state: execute.State,
  secret: fn(String) -> Result(String, String),
) -> Result(Workspace, String) {
  let state = execute.State(..state, root: Some(filepath.directory_name(file)))
  use #(source, type_, state, _) <- result.try(execute.prepare_configuration(
    code,
    state,
    check_workspace,
  ))
  evaluate(file, source, type_, state, secret)
}

fn evaluate(file, source, type_, state, secret) {
  let span =
    tracing.start("eyg.cloud.configuration", None, [
      #("eyg.cloud.file", tracing.text(file)),
    ])
  let host =
    execute.Host(
      ..execute.configuration_host(secret),
      trace: Some(tracing.context(span)),
    )
  let #(execute.Run(result:, ..), state) =
    execute.run_configuration_source(
      source,
      execute.configuration(),
      host,
      state,
    )
  tracing.end(span, [], case result {
    Ok(_) -> None
    Error(reason) -> Some(reason)
  })
  case result {
    Ok(Some(value)) -> decode(value, type_, file, state)
    Ok(None) -> Error(file <> " has no value")
    Error(reason) -> Error(file <> ": " <> reason)
  }
}

fn check_workspace(type_) {
  use channel <- result.try(check.field(type_, "channel"))
  use config <- result.try(check.call(channel, channel_info_type()))
  use shell <- result.try(check.field(config, "channel_shell"))
  use _ <- result.try(execute.check_shell(shell))
  use on_input <- result.try(check.field(config, "on_input"))
  let callbacks = case check.fields(on_input) {
    Ok(fields) -> list.map(fields, fn(field) { field.1 })
    Error(_) -> [on_input]
  }
  use _ <- result.try(list.try_each(callbacks, handler.check(_, t.Var(-100))))
  Ok(Nil)
}

fn channel_info_type() {
  t.record([
    #("platform", t.String),
    #("installation", t.String),
    #("id", t.String),
    #("name", t.String),
  ])
}

fn decode(value, type_, file, state) {
  let directory = filepath.directory_name(file)
  use llm <- result.try(field("llm", overlay.cast_llm, value))
  use readme <- result.try(optional_string("readme", value))
  use channel <- result.try(field("channel", Ok, value))
  use channel_type <- result.try(check.field(type_, "channel"))
  use files <- result.try(case cast.field("files", Ok, value) {
    Ok(_) ->
      field("files", cast.as_string, value)
      |> result.map(fn(path) {
        Some(case filepath.is_absolute(path) {
          True -> path
          False -> filepath.join(directory, path)
        })
      })
    Error(_) -> Ok(None)
  })
  use crons <- result.try(case cast.field("crons", Ok, value) {
    Ok(_) -> field("crons", cast.as_list_of(_, decode_cron), value)
    Error(_) -> Ok([])
  })
  use connections <- result.try(case cast.field("connections", Ok, value) {
    Ok(_) -> field("connections", cast.as_list_of(_, connection.decode), value)
    Error(_) -> Ok([])
  })
  Ok(Workspace(
    llm:,
    readme:,
    channel:,
    channel_type:,
    files:,
    crons:,
    connections:,
    state:,
  ))
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
  let platform_name = channel.platform(platform)
  use type_ <- result.try(check.call(
    workspace.channel_type,
    channel_info_type(),
  ))
  use on_input <- result.try(check.field(type_, "on_input"))
  use on_input <- result.try(handler.select_type(on_input, platform_name))
  use _ <- result.try(
    handler.check(on_input, info.input_type)
    |> result.map_error(fn(reason) { "on_input: " <> reason }),
  )
  let argument =
    v.Record(
      dict.from_list([
        #("platform", v.String(channel.platform(platform))),
        #("installation", v.String(platform)),
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
      use handle <- result.try(field("on_input", Ok, value))
      use handle <- result.try(
        handler.select(handle, platform_name)
        |> result.map_error(simple_debug.describe),
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
      use llm <- result.try(case cast.field("llm", Ok, value) {
        Ok(_) -> field("llm", overlay.cast_llm, value)
        Error(_) -> Ok(workspace.llm)
      })
      Ok(Channel(handle:, shell:, readme:, triggers:, llm:))
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
