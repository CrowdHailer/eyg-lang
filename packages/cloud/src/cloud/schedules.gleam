//// Schedule registration shared by cloud startup and `gleam dev cron`.

import cloud/beam/execute
import cloud/discord/client
import cloud/schedule
import gleam/dict
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleam/time/timestamp

pub fn load(state: execute.State) {
  case dict.get(state.secrets, "DISCORD_BOT_TOKEN") {
    Error(_) -> Ok(#([], state))
    Ok(token) -> {
      use guild <- result.try(
        dict.get(state.secrets, "DISCORD_GUILD_ID")
        |> result.replace_error("Noise check-in requires DISCORD_GUILD_ID"),
      )
      use channels <- result.try(
        client.guild_channels(token, guild)
        |> result.map_error(fn(reason) {
          "Discord channels: " <> string.inspect(reason)
        }),
      )
      use channel <- result.try(
        case list.filter(channels, fn(channel) { channel.name == "noise" }) {
          [channel] -> Ok(channel)
          [] -> Error("Noise check-in: no Discord channel named noise")
          _ ->
            Error("Noise check-in: more than one Discord channel named noise")
        },
      )
      schedule.prepare(
        [noise(guild, channel.id)],
        timestamp.system_time(),
        state,
      )
    }
  }
}

/// Bind the example to the actual guild/channel IDs, never a name-based session.
/// TODO this is cheating it should be up to the agent/harness to decide how to notify
pub fn noise(guild_id: String, channel_id: String) -> schedule.Config {
  let session_id = "Discord:" <> guild_id <> ":" <> channel_id
  let content = "Scheduled check-in: hello from the five-minute cron!"
  let body =
    json.object([
      #("content", json.string(content)),
      #(
        "allowed_mentions",
        json.object([#("parse", json.array([], json.string))]),
      ),
    ])
    |> json.to_string
  let reply_code = "
match perform Env(\"DISCORD_BOT_TOKEN\") {
  Some(token) -> {
    perform Fetch({
      method: POST({}), scheme: HTTPS({}), host: \"discord.com\", port: None({}),
      path: " <> literal("/api/v10/channels/" <> channel_id <> "/messages") <> ",
      query: None({}),
      headers: [
        {key: \"authorization\", value: !string_append(\"Bot \", token)},
        {key: \"content-type\", value: \"application/json\"}
      ],
      body: !string_to_binary(" <> literal(body) <> ")
    })
  }
  None(_) -> { Error(\"DISCORD_BOT_TOKEN is not configured\") }
}"
  let prompt =
    "This is the five-minute Discord #noise check-in. Post exactly one message to this channel: "
    <> content
    <> "\n"
    <> "Your final answer and StandardOut are not delivered anywhere: scheduled printing is a no-op. "
    <> "You must use the run tool to perform Fetch to send the Discord message. "
    <> "The following EYG code reads the bot token without displaying it and posts to the correct channel. "
    <> "Execute it once, check that the response status is 200 or 201, and then finish. "
    <> "Do not post a second message after a successful response.\n```eyg\n"
    <> reply_code
    <> "\n```"
  let code = "(_) -> {
  {session_id: " <> literal(session_id) <> ", payload: Text(" <> literal(prompt) <> ")}
}"
  schedule.Config("Noise check-in", "*/5 * * * *", code)
}

fn literal(text: String) -> String {
  json.to_string(json.string(text))
}
