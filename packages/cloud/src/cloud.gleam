import bucket
import cloud/apex/access
import cloud/apex/context.{Context}
import cloud/apex/server
import cloud/apex/web
import cloud/beam/execute
import cloud/box/memory
import cloud/channels
import cloud/crons
import cloud/data/blobs
import cloud/data/db
import cloud/data/migrations
import cloud/data/pool
import cloud/discord/discord
import cloud/live
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
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama
import simplifile

/// Shared runtime configuration for the service and one-shot dev commands.
/// The llm is Ollama's cloud, it is only available when `OLLAMA_API_KEY` is set.
pub fn setup() {
  let slack_token = envoy.get("SLACK_BOT_TOKEN")
  let discord_token = envoy.get("DISCORD_BOT_TOKEN")
  let ollama_token = envoy.get("OLLAMA_API_KEY")
  let llm = case ollama_token {
    Ok(token) if token != "" ->
      Some(provider.Llm(provider.Ollama(ollama.cloud(token)), "glm-5.3:cloud"))
    _ -> None
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
  let api = start_api(state, llm)
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
  // Discord channels have durable sessions in a box that is chosen explicitly.
  case
    dict.get(state.secrets, "DISCORD_BOT_TOKEN"),
    api,
    envoy.get("DISCORD_BOX")
  {
    Ok(token), Some(context), Ok(box) -> {
      let assert Ok(guild) = envoy.get("DISCORD_GUILD_ID")
      let llm = option.map(llm, fn(llm: provider.Llm) { llm.model })
      let assert Ok(channels) = channels.start(context, box, llm)
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
    Ok(_), None, _ ->
      io.println_error("Discord needs a database, its sessions are kept there")
    Ok(_), _, Error(Nil) ->
      io.println_error(
        "Discord needs DISCORD_BOX, the name of the box its channels have sessions in",
      )
    Error(_), _, _ -> Nil
  }
  process.sleep_forever()
}

/// The API and web interface are only available when a database is configured,
/// with `DATABASE_URL` or `POSTGRES_HOST` and `POSTGRES_PASSWORD`. Migrations are applied when they start.
/// Blocks are kept in a bucket, Railway's blob storage or any S3 compatible store, set by the `S3_` variables.
/// They only accept local connections unless `ACCESS_PASSWORD` is set, see `cloud/apex/access`.
/// Sessions can chat with the configured llm, if there is one, by the name of its model.
fn start_api(state, llm: Option(provider.Llm)) {
  let database = case envoy.get("DATABASE_URL"), envoy.get("POSTGRES_HOST") {
    Ok(url), _ -> Some(pool.Url(url))
    Error(Nil), Ok(host) -> {
      let assert Ok(password) = envoy.get("POSTGRES_PASSWORD")
      Some(pool.Postgres(host:, password:))
    }
    Error(Nil), Error(Nil) -> None
  }
  case database {
    None -> None
    Some(database) -> {
      let assert Ok(started) = pool.start(process.new_name("db_pool"), database)
      migrations.apply_all(started.data)
      let db = db.Pool(started.data)
      let assert Ok(blobs) = s3_blobs()
      let state = execute.State(..state, blobs: blobs.data)
      let access = case envoy.get("ACCESS_PASSWORD") {
        Ok(password) if password != "" -> access.Password(password)
        _ -> access.Local
      }
      let assert Ok(policy) = simplifile.read("policy.eyg")
      let port =
        envoy.get("PORT") |> result.try(int.parse) |> result.unwrap(8080)
      let assert Ok(boxes) = registry.start()
      let assert Ok(sessions) = registry.start()
      let assert Ok(memory) = memory.start()
      let assert Ok(live) = live.start()
      let context =
        Context(
          db:,
          boxes: boxes.data,
          memory: memory.data,
          sessions: sessions.data,
          state:,
          policy:,
          llms: case llm {
            Some(llm) -> dict.from_list([#(llm.model, llm)])
            None -> dict.new()
          },
          live:,
        )
      let assert Ok(_) = server.start(context, access, port)
      let web_port =
        envoy.get("WEB_PORT") |> result.try(int.parse) |> result.unwrap(8787)
      let assert Ok(_) = web.start(context, access, web_port)
      let assert Ok(_) = crons.start(context)
      Some(context)
    }
  }
}

fn s3_blobs() {
  let assert Ok(endpoint) = envoy.get("S3_ENDPOINT") |> result.try(uri.parse)
  let assert Some(host) = endpoint.host
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
      host:,
      region:,
      access_key_id:,
      secret_access_key:,
      session_token: None,
    )
  blobs.s3(credentials, bucket)
}
