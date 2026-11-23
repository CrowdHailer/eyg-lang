import cloud/app
import cloud/discord/discord
import cloud/schedule
import cloud/schedules
import cloud/session
import cloud/slack/slack
import cloud/trigger
import envoy
import gleam/dict
import gleam/erlang/process
import simplifile

pub fn main(bucket) -> Nil {
  let #(state, llm) = app.setup(bucket)
  let assert Ok(#(schedules, state)) = schedules.load(state)
  let assert Ok(code) = simplifile.read("right_on.eyg")
  let discord_triggers = [#("Right on", code)]
  // TODO keep this execute_state
  let assert Ok(#(discord_triggers, state)) =
    trigger.prepare(discord_triggers, discord.trigger_type(), state)
  let assert Ok(code) = simplifile.read("right_on_slack.eyg")
  let assert Ok(#(slack_triggers, state)) =
    trigger.prepare([#("Right on", code)], slack.trigger_type(), state)
  let assert Ok(sessions) =
    session.start(state.origin, llm, state.secrets, bucket)
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
