//// The service: its database, the boxes, shells and chats, and the server.

import cloud/apex/access
import cloud/apex/context.{type Context, Context}
import cloud/apex/server
import cloud/beam/execute
import cloud/config.{type Config}
import cloud/data/db
import cloud/data/migrations
import cloud/db/pool
import cloud/registry
import envoy
import eyg/hub/cache
import gleam/dict
import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/result
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama
import pog
import simplifile

/// Shared runtime configuration for the service and one-shot dev commands.
/// The llm is Ollama's cloud, it is only available when `OLLAMA_API_KEY` is set.
pub fn setup(bucket) {
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
  let state =
    execute.State(
      origin: hub,
      cache: cache.ready(),
      secrets:,
      bucket:,
      pins: dict.new(),
    )
  #(state, llm)
}

/// Migrations are applied when the service starts.
/// The server only accepts local connections unless there is an access password, see `cloud/apex/access`.
/// Chats can be with the configured llm, if there is one, by the name of its model.
pub fn start(config: Config, state, llm: Option(provider.Llm)) -> Context {
  let pool_name = process.new_name("db_pool")
  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(pool.supervised(pool_name, config.postgres))
    |> supervisor.start
  let conn = pog.named_connection(pool_name)
  migrations.apply_all(conn)
  let assert Ok(policy) = simplifile.read("policy.eyg")
  let assert Ok(boxes) = registry.start()
  let assert Ok(shells) = registry.start()
  let assert Ok(chats) = registry.start()
  let context =
    Context(
      db: db.Pool(conn),
      boxes: boxes.data,
      shells: shells.data,
      chats: chats.data,
      state:,
      policy:,
      llms: case llm {
        Some(llm) -> dict.from_list([#(llm.model, llm)])
        None -> dict.new()
      },
    )
  let access = case config.access_password {
    Ok(password) -> access.Password(password)
    Error(Nil) -> access.Local
  }
  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(server.supervised(context, access, config.port))
    |> supervisor.start
  context
}
