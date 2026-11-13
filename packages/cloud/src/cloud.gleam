import cloud/beam/execute
import cloud/discord/discord
import cloud/session
import cloud/slack/slack
import cloud/trigger
import envoy
import eyg/hub/cache
import gleam/dict
import gleam/erlang/process
import gleam/result
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama
import simplifile

pub fn main() -> Nil {
  let slack_token = envoy.get("SLACK_BOT_TOKEN")
  let discord_token = envoy.get("DISCORD_BOT_TOKEN")
  let ollama_token = envoy.get("OLLAMA_API_KEY")
  let llm = case ollama_token {
    Ok(token) ->
      provider.Llm(provider.Ollama(ollama.cloud(token)), "glm-5.3:cloud")
    Error(_) ->
      provider.Llm(provider.Ollama(ollama.local()), "devstral-small-2:24b")
  }
  case slack_token, discord_token {
    Error(_), Error(_) -> panic as "Set SLACK_BOT_TOKEN or DISCORD_BOT_TOKEN"
    _, _ -> Nil
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
  let assert Ok(code) = simplifile.read("right_on.eyg")
  let discord_triggers = [#("Right on", code)]
  // TODO keep this execute_state
  let assert Ok(#(discord_triggers, _)) =
    trigger.prepare(
      discord_triggers,
      discord.trigger_type(),
      execute.State(origin: hub, cache: cache.ready(), secrets:),
    )
  let assert Ok(code) = simplifile.read("right_on_slack.eyg")
  let assert Ok(#(slack_triggers, _)) =
    trigger.prepare(
      [#("Right on", code)],
      slack.trigger_type(),
      execute.State(origin: hub, cache: cache.ready(), secrets:),
    )
  let assert Ok(sessions) = session.start(hub, llm, secrets)
  case slack_token {
    Ok(token) -> {
      let assert Ok(_) =
        slack.start_channel(sessions.data, token, slack_triggers)
      Nil
    }
    Error(_) -> Nil
  }
  case discord_token {
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
