//// Slack, Discord and the scheduled check-in, started beside the service.

import cloud/apex/context.{type Context}
import cloud/channels
import cloud/discord/discord
import cloud/schedule
import cloud/schedules
import cloud/session
import cloud/slack/slack
import cloud/trigger
import envoy
import gleam/dict
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import overlay/llm/provider
import simplifile

pub fn start(context: Context, state, llm: Option(provider.Llm)) -> Nil {
  // The check-in to the #noise channel is a demo, it only runs when asked for.
  let #(schedules, state) = case envoy.get("DISCORD_NOISE") {
    Error(Nil) -> #([], state)
    Ok(_) ->
      case schedules.load(state) {
        Ok(loaded) -> loaded
        Error(reason) -> {
          io.println_error(reason)
          #([], state)
        }
      }
  }
  let assert Ok(code) = simplifile.read("right_on.eyg")
  let discord_triggers = [#("Right on", code)]
  // TODO keep this execute_state
  let assert Ok(#(discord_triggers, state)) =
    trigger.prepare(discord_triggers, discord.trigger_type(), state)
  let assert Ok(code) = simplifile.read("right_on_slack.eyg")
  let assert Ok(#(slack_triggers, state)) =
    trigger.prepare([#("Right on", code)], slack.trigger_type(), state)
  let assert Ok(sessions) =
    session.start(state.origin, llm, state.secrets, state.bucket)
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
  // Discord channels are durable chats in a box that is chosen explicitly.
  case
    dict.get(state.secrets, "DISCORD_BOT_TOKEN"),
    envoy.get("DISCORD_BOX"),
    llm
  {
    Ok(token), Ok(box), Some(llm) -> {
      let assert Ok(guild) = envoy.get("DISCORD_GUILD_ID")
      let assert Ok(channels) = channels.start(context, box, llm.model)
      let selected =
        envoy.get("DISCORD_CHANNELS")
        |> result.map(fn(names) {
          string.split(names, ",") |> list.map(string.trim)
        })
        |> option.from_result
      let assert Ok(_) =
        discord.start_channel(
          sessions.data,
          channels,
          token,
          guild,
          selected,
          discord_triggers,
        )
      Nil
    }
    Ok(_), Error(Nil), _ ->
      io.println_error(
        "Discord needs DISCORD_BOX, the name of the box its channels chat in",
      )
    Ok(_), _, None ->
      io.println_error("Discord needs an llm to chat with, see OLLAMA_API_KEY")
    Error(_), _, _ -> Nil
  }
}
