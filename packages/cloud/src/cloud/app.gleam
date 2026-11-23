//// The service: its database, the boxes, shells and chats, and the server.

import cloud/apex/context.{type Context, Context}
import cloud/apex/server
import cloud/beam/execute
import cloud/config.{type Config}
import cloud/data/db
import cloud/db/pool
import cloud/registry
import envoy
import eyg/hub/cache
import gleam/dict
import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import gleam/result
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama
import pog
import simplifile

/// Shared runtime configuration for the service and one-shot dev commands.
pub fn setup(bucket) {
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

/// Chats can be with the configured llm, by the name of its model.
pub fn start(config: Config, state, llm: provider.Llm) -> Context {
  let pool_name = process.new_name("db_pool")
  let assert Ok(policy) = simplifile.read("policy.eyg")
  let assert Ok(boxes) = registry.start()
  let assert Ok(shells) = registry.start()
  let assert Ok(chats) = registry.start()
  let context =
    Context(
      db: db.Pool(pog.named_connection(pool_name)),
      boxes: boxes.data,
      shells: shells.data,
      chats: chats.data,
      state:,
      policy:,
      llms: dict.from_list([#(llm.model, llm)]),
    )
  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(pool.supervised(pool_name, config.postgres))
    |> supervisor.add(server.supervised(context, config.port))
    |> supervisor.start
  context
}
