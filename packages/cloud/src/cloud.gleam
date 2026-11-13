//// Run a workspace and connect it to chat platforms.
////
//// - `WORKSPACE` the workspace configuration file, defaults to `workspace.eyg`.
//// - `CHAT_ORIGIN` connect the example chat app at this origin, i.e. `http://localhost:8080`.
//// - `SLACK_BOT_TOKEN` run EYG commands posted in Slack.
//// - `DISCORD_BOT_TOKEN` and `DISCORD_GUILD_ID` run EYG commands posted in Discord.
//// - `EYG_ORIGIN` the hub packages are loaded from, defaults to `https://eyg.run`.

import cloud/beam/execute
import cloud/config
import cloud/discord/discord
import cloud/plugins/example_chat
import cloud/slack/slack
import cloud/system
import cloud/workspace
import envoy
import eyg/hub/cache
import gleam/erlang/process
import gleam/io
import gleam/option.{None}
import gleam/result
import ogre/origin

pub fn main() -> Nil {
  system.configure_proxy()
  let assert Ok(hub) =
    envoy.get("EYG_ORIGIN")
    |> result.unwrap("https://eyg.run")
    |> origin.from_string_strict
  let file = envoy.get("WORKSPACE") |> result.unwrap("workspace.eyg")
  let state = execute.State(origin: hub, cache: cache.ready(), root: None)
  let load = config.loader(file, state)
  let workspace = case workspace.start(load) {
    Ok(workspace) -> workspace
    Error(reason) -> panic as reason
  }
  io.println("Workspace loaded from " <> file)

  case envoy.get("CHAT_ORIGIN") {
    Ok(origin) -> {
      let config = example_chat.Config(origin:, poll_interval: 500)
      let emit = fn(event) { process.send(workspace, workspace.Inbound(event)) }
      let assert Ok(outbound) = example_chat.start(config, emit)
      process.send(
        workspace,
        workspace.Connect(example_chat.platform, outbound),
      )
      io.println("Connected to example chat at " <> origin)
    }
    Error(Nil) -> Nil
  }

  case envoy.get("SLACK_BOT_TOKEN") {
    Ok(token) -> {
      let assert Ok(_) = slack.start_channel(hub, token)
      Nil
    }
    Error(Nil) -> Nil
  }

  case envoy.get("DISCORD_BOT_TOKEN") {
    Ok(token) -> {
      let assert Ok(guild) = envoy.get("DISCORD_GUILD_ID")
      let assert Ok(_) = discord.start_channel(hub, token, guild)
      Nil
    }
    Error(Nil) -> Nil
  }
  process.sleep_forever()
}
