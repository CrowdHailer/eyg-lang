import cloud/discord/discord
import cloud/session
import cloud/slack/slack
import envoy
import gleam/erlang/process
import gleam/result
import ogre/origin

pub fn main() -> Nil {
  let slack_token = envoy.get("SLACK_BOT_TOKEN")
  let discord_token = envoy.get("DISCORD_BOT_TOKEN")
  case slack_token, discord_token {
    Error(_), Error(_) -> panic as "Set SLACK_BOT_TOKEN or DISCORD_BOT_TOKEN"
    _, _ -> Nil
  }
  let assert Ok(hub) =
    envoy.get("EYG_ORIGIN")
    |> result.unwrap("https://eyg.run")
    |> origin.from_string_strict
  case slack_token {
    Ok(token) -> {
      let assert Ok(_) = slack.start_channel(hub, token)
      Nil
    }
    Error(_) -> Nil
  }
  case discord_token {
    Ok(token) -> {
      let assert Ok(guild) = envoy.get("DISCORD_GUILD_ID")
      let assert Ok(sessions) = session.start(hub)
      let assert Ok(_) = discord.start_channel(sessions.data, token, guild)
      Nil
    }
    Error(_) -> Nil
  }
  process.sleep_forever()
}
