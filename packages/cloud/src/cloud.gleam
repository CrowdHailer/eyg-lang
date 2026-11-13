//// Run a cloud: the workspaces in `cloud.eyg`, their connections, the web shell and the API.
////
//// - `CLOUD` the cloud configuration file, defaults to `cloud.eyg`, see `cloud/instance`.
//// - `WORKSPACE` without a `cloud.eyg`, run this one workspace, defaults to `workspace.eyg`.
//// - `EYG_ORIGIN` the hub packages are loaded from, defaults to `https://eyg.run`.
//// - `PORT` the port the web server listens on, defaults to 8081.
//// - `CLOUD_ORIGIN` the public origin of the server, defaults to `http://localhost:<PORT>`.

import cloud/api
import cloud/artifacts
import cloud/beam/execute
import cloud/discord/discord
import cloud/instance
import cloud/registry
import cloud/schedule
import cloud/schedules
import cloud/server
import cloud/session
import cloud/slack/slack
import cloud/tracing
import cloud/trigger
import cloud/web/runner
import cloud/workspace
import envoy
import eyg/hub/cache
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama
import simplifile

/// Shared runtime configuration for the service and one-shot dev commands.
pub fn setup() {
  let slack_token = envoy.get("SLACK_BOT_TOKEN")
  let discord_token = envoy.get("DISCORD_BOT_TOKEN")
  let ollama_token = envoy.get("OLLAMA_API_KEY")
  let llm = case ollama_token {
    Ok(token) ->
      provider.Llm(provider.Ollama(ollama.cloud(token)), "glm-5.3:cloud")
    Error(_) ->
      provider.Llm(provider.Ollama(ollama.local()), "devstral-small-2:24b")
  }
  let assert Ok(hub) =
    envoy.get("EYG_ORIGIN")
    |> result.unwrap("https://eyg.run")
    |> origin.from_string_strict
  let secrets = case discord_token {
    Ok(token) -> dict.from_list([#("DISCORD_BOT_TOKEN", token)])
    Error(_) -> dict.new()
  }
  let secrets = case slack_token {
    Ok(token) -> dict.insert(secrets, "SLACK_BOT_TOKEN", token)
    Error(_) -> secrets
  }
  let secrets = case envoy.get("DISCORD_GUILD_ID") {
    Ok(guild) -> dict.insert(secrets, "DISCORD_GUILD_ID", guild)
    Error(_) -> secrets
  }
  #(
    execute.State(
      origin: hub,
      cache: cache.ready(),
      root: None,
      files: None,
      secrets:,
    ),
    llm,
  )
}

pub fn main() -> Nil {
  let #(state, llm) = setup()
  let cloud_file = envoy.get("CLOUD") |> result.unwrap("cloud.eyg")
  let workspace_file = envoy.get("WORKSPACE") |> result.unwrap("workspace.eyg")
  case simplifile.is_file(cloud_file), simplifile.is_file(workspace_file) {
    Ok(True), _ | _, Ok(True) -> configured(state.origin)
    _, _ -> basic(state, llm)
  }
}

/// Preserve main's startup schedules and native adapters.
fn basic(state, llm) {
  let assert Ok(#(schedules, state)) = schedules.load(state)
  let assert Ok(code) = simplifile.read("right_on.eyg")
  let discord_triggers = [#("Right on", code)]
  // TODO keep this execute_state
  let assert Ok(#(discord_triggers, state)) =
    trigger.prepare(discord_triggers, discord.trigger_type(), state)
  let assert Ok(code) = simplifile.read("right_on_slack.eyg")
  let assert Ok(#(slack_triggers, state)) =
    trigger.prepare([#("Right on", code)], slack.trigger_type(), state)
  let assert Ok(sessions) = session.start(state.origin, llm, state.secrets)
  let assert Ok(runtime) = schedule.runtime(state)
  let assert Ok(_) = schedule.start(schedules, sessions.data, runtime)
  case dict.get(state.secrets, "SLACK_BOT_TOKEN") {
    Ok(token) -> {
      let assert Ok(_) =
        slack.start_channel(sessions.data, token, slack_triggers)
      Nil
    }
    Error(_) -> Nil
  }
  case dict.get(state.secrets, "DISCORD_BOT_TOKEN") {
    Ok(token) -> {
      let assert Ok(guild) = envoy.get("DISCORD_GUILD_ID")
      let assert Ok(_) =
        discord.start_channel(sessions.data, token, guild, discord_triggers)
      Nil
    }
    Error(_) -> Nil
  }
  process.sleep_forever()
}

fn configured(hub) {
  let state =
    execute.State(
      origin: hub,
      cache: cache.ready(),
      root: None,
      files: None,
      secrets: dict.new(),
    )
  let cloud_file = envoy.get("CLOUD") |> result.unwrap("cloud.eyg")
  let #(load, instance) = case simplifile.is_file(cloud_file) {
    Ok(True) -> {
      let load = instance.loader(cloud_file, state)
      case load() {
        Ok(instance) -> #(load, instance)
        Error(reason) -> panic as reason
      }
    }
    _ -> {
      let file = envoy.get("WORKSPACE") |> result.unwrap("workspace.eyg")
      let instance = instance.single("default", file, state)
      #(fn() { Ok(instance.single("default", file, state)) }, instance)
    }
  }
  let port = envoy.get("PORT") |> result.try(int.parse) |> result.unwrap(8081)
  let origin =
    envoy.get("CLOUD_ORIGIN")
    |> result.unwrap("http://localhost:" <> int.to_string(port))
  let assert Ok(_) = tracing.start_tracer()
  let assert Ok(artifacts) = artifacts.start(origin)
  let entries =
    list.map(instance.workspaces, fn(entry) { #(entry.name, entry.file) })
  let shells = list.map(instance.shells, fn(shell) { shell.0 })
  let registry = case registry.start(entries, shells, state, artifacts) {
    Ok(registry) -> registry
    Error(reason) -> panic as reason
  }
  let handles = process.call(registry, 5000, registry.Workspaces)
  list.each(handles, fn(handle) {
    process.send(
      handle.workspace,
      workspace.SetApi(api.perform(registry, state, _)),
    )
    io.println("Workspace " <> handle.name <> " loaded from " <> handle.file)
  })
  // A delivery goes to the first workspace with a connection of that name.
  let webhook = fn(name, request) {
    list.fold_until(
      handles,
      Error("no connection named " <> name),
      fn(_, handle) {
        case
          process.call(handle.workspace, 5000, workspace.Webhook(
            name,
            request,
            _,
          ))
          |> result.map(fn(respond) { respond() })
        {
          Error("no connection named " <> _) as error -> list.Continue(error)
          result -> list.Stop(result)
        }
      },
    )
  }
  let web = runner.Context(registry:, instance: load, state:)
  let assert Ok(_) =
    server.start(port, server.Context(artifacts, webhook, Some(web)))
  io.println("Serving at " <> origin)
  process.sleep_forever()
}
