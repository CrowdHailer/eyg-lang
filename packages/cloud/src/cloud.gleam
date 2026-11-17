import bucket
import cloud/apex/context.{Context}
import cloud/apex/server
import cloud/beam/execute
import cloud/box/memory
import cloud/data/blobs
import cloud/data/db
import cloud/data/pool
import cloud/discord/discord
import cloud/registry
import cloud/schedule
import cloud/schedules
import cloud/session
import cloud/slack/slack
import cloud/trigger
import envoy
import eyg/hub/cache
import gleam/dict
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/option.{None, Some}
import gleam/result
import gleam/uri
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
  let assert Ok(blobs) = blobs.start()
  let state =
    execute.State(
      origin: hub,
      cache: cache.ready(),
      secrets:,
      blobs: blobs.data,
      pins: dict.new(),
    )
  #(state, llm)
}

pub fn main() -> Nil {
  let #(state, llm) = setup()
  let assert Ok(#(schedules, state)) = schedules.load(state)
  let assert Ok(code) = simplifile.read("right_on.eyg")
  let discord_triggers = [#("Right on", code)]
  // TODO keep this execute_state
  let assert Ok(#(discord_triggers, state)) =
    trigger.prepare(discord_triggers, discord.trigger_type(), state)
  let assert Ok(code) = simplifile.read("right_on_slack.eyg")
  let assert Ok(#(slack_triggers, state)) =
    trigger.prepare([#("Right on", code)], slack.trigger_type(), state)
  start_api(state, llm)
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

/// The API is only available when a database is configured.
/// Sessions can chat with the configured llm, by the name of its model.
fn start_api(state, llm: provider.Llm) {
  case envoy.get("POSTGRES_HOST") {
    Error(Nil) -> Nil
    Ok(host) -> {
      let assert Ok(password) = envoy.get("POSTGRES_PASSWORD")
      let assert Ok(started) =
        pool.start(process.new_name("db_pool"), pool.Postgres(host:, password:))
      let assert Ok(endpoint) =
        envoy.get("S3_ENDPOINT") |> result.try(uri.parse)
      let assert Some(s3_host) = endpoint.host
      let assert Ok(scheme) =
        http.scheme_from_string(option.unwrap(endpoint.scheme, "https"))
      let assert Ok(region) = envoy.get("S3_REGION")
      let assert Ok(bucket) = envoy.get("S3_BUCKET")
      let assert Ok(access_key_id) = envoy.get("S3_ACCESS_KEY_ID")
      let assert Ok(secret_access_key) = envoy.get("S3_SECRET_ACCESS_KEY")
      let credentials =
        bucket.Credentials(
          scheme:,
          port: endpoint.port,
          host: s3_host,
          region:,
          access_key_id:,
          secret_access_key:,
          session_token: None,
        )
      let assert Ok(blobs) = blobs.s3(credentials, bucket)
      let state = execute.State(..state, blobs: blobs.data)
      let assert Ok(policy) = simplifile.read("policy.eyg")
      let port =
        envoy.get("PORT") |> result.try(int.parse) |> result.unwrap(8080)
      let assert Ok(boxes) = registry.start()
      let assert Ok(sessions) = registry.start()
      let assert Ok(memory) = memory.start()
      let context =
        Context(
          db: db.Pool(started.data),
          boxes: boxes.data,
          memory: memory.data,
          sessions: sessions.data,
          state:,
          policy:,
          llms: dict.from_list([#(llm.model, llm)]),
        )
      let assert Ok(_) = server.start(context, port)
      Nil
    }
  }
}
