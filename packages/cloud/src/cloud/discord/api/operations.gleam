import cloud/discord/api/pagination
import cloud/discord/api/schema
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/uri
import oas/generator/utils

pub type Failure {
  DiscordError(schema.ApiError)
  RateLimited(retry_after_seconds: Float)
  UnexpectedStatus(response.Response(BitArray))
}

/// https://discord.com/developers/docs/resources/user#get-current-user
pub fn current_user_request(
  base: request.Request(BitArray),
) -> request.Request(BitArray) {
  base
  |> utils.set_method(http.Get)
  |> utils.append_path("/users/@me")
}

pub fn current_user_response(
  response: response.Response(BitArray),
) -> Result(Result(schema.Identity, Failure), json.DecodeError) {
  decode_response(response, schema.identity_decoder())
}

/// Reply to a message without pinging its author or mentions in program output.
pub fn create_message_request(
  base: request.Request(BitArray),
  channel: String,
  message: String,
  text: String,
) -> request.Request(BitArray) {
  let body =
    json.object([
      #("content", json.string(text)),
      #(
        "message_reference",
        json.object([
          #("message_id", json.string(message)),
          #("fail_if_not_exists", json.bool(False)),
        ]),
      ),
      #(
        "allowed_mentions",
        json.object([
          #("parse", json.preprocessed_array([])),
          #("replied_user", json.bool(False)),
        ]),
      ),
    ])
    |> json.to_string
  base
  |> utils.set_method(http.Post)
  |> utils.append_path("/channels/" <> channel <> "/messages")
  |> utils.set_body("application/json; charset=utf-8", <<body:utf8>>)
}

pub fn create_message_response(
  response: response.Response(BitArray),
) -> Result(Result(Nil, Failure), json.DecodeError) {
  decode_response(response, decode.success(Nil))
}

/// https://discord.com/developers/docs/resources/guild#get-guild
pub fn guild_request(
  base: request.Request(BitArray),
  guild: String,
) -> request.Request(BitArray) {
  base
  |> utils.set_method(http.Get)
  |> utils.append_path("/guilds/" <> guild)
}

pub fn guild_response(
  response: response.Response(BitArray),
) -> Result(Result(schema.Guild, Failure), json.DecodeError) {
  decode_response(response, schema.guild_decoder())
}

/// Guild channel discovery is not paginated and does not include threads.
pub fn guild_channels_request(
  base: request.Request(BitArray),
  guild: String,
) -> request.Request(BitArray) {
  base
  |> utils.set_method(http.Get)
  |> utils.append_path("/guilds/" <> guild <> "/channels")
}

pub fn guild_channels_response(
  response: response.Response(BitArray),
) -> Result(Result(List(schema.Channel), Failure), json.DecodeError) {
  decode_response(response, decode.list(schema.channel_decoder()))
}

/// Discord returns up to 100 messages after the exclusive snowflake boundary.
/// https://docs.discord.com/developers/resources/message#get-channel-messages
pub fn channel_messages_request(
  base: request.Request(BitArray),
  channel: String,
  after after: String,
) -> request.Request(BitArray) {
  base
  |> utils.set_method(http.Get)
  |> utils.append_path("/channels/" <> channel <> "/messages")
  |> request.set_query([#("limit", "100"), #("after", after)])
}

pub fn channel_messages_response(
  response: response.Response(BitArray),
) -> Result(
  Result(pagination.Page(List(schema.Message)), Failure),
  json.DecodeError,
) {
  decode_response(response, pagination.decoder())
}

/// Post a message, mentions of users notify them, other mentions do not.
/// A thread is posted to with the thread's id as the channel.
pub fn post_message_request(
  base: request.Request(BitArray),
  channel: String,
  text: String,
) -> request.Request(BitArray) {
  let body =
    json.object([
      #("content", json.string(text)),
      #(
        "allowed_mentions",
        json.object([#("parse", json.array(["users"], json.string))]),
      ),
    ])
    |> json.to_string
  base
  |> utils.set_method(http.Post)
  |> utils.append_path("/channels/" <> channel <> "/messages")
  |> utils.set_body("application/json; charset=utf-8", <<body:utf8>>)
}

pub fn post_message_response(
  response: response.Response(BitArray),
) -> Result(Result(String, Failure), json.DecodeError) {
  decode_response(response, decode.field("id", decode.string, decode.success))
}

/// The most recent messages in a channel, newest first.
/// https://docs.discord.com/developers/resources/message#get-channel-messages
pub fn recent_messages_request(
  base: request.Request(BitArray),
  channel: String,
  limit: Int,
) -> request.Request(BitArray) {
  base
  |> utils.set_method(http.Get)
  |> utils.append_path("/channels/" <> channel <> "/messages")
  |> request.set_query([#("limit", int.to_string(limit))])
}

pub fn recent_messages_response(
  response: response.Response(BitArray),
) -> Result(Result(List(schema.Post), Failure), json.DecodeError) {
  decode_response(response, decode.list(schema.post_decoder()))
}

/// https://docs.discord.com/developers/resources/message#get-channel-message
pub fn get_message_request(
  base: request.Request(BitArray),
  channel: String,
  message: String,
) -> request.Request(BitArray) {
  base
  |> utils.set_method(http.Get)
  |> utils.append_path("/channels/" <> channel <> "/messages/" <> message)
}

pub fn get_message_response(
  response: response.Response(BitArray),
) -> Result(Result(schema.Post, Failure), json.DecodeError) {
  decode_response(response, schema.post_decoder())
}

/// Every active thread in a guild, the bot only sees threads in channels it can read.
/// https://docs.discord.com/developers/resources/guild#list-active-guild-threads
pub fn active_threads_request(
  base: request.Request(BitArray),
  guild: String,
) -> request.Request(BitArray) {
  base
  |> utils.set_method(http.Get)
  |> utils.append_path("/guilds/" <> guild <> "/threads/active")
}

pub fn active_threads_response(
  response: response.Response(BitArray),
) -> Result(Result(List(schema.Thread), Failure), json.DecodeError) {
  decode_response(response, schema.active_threads_decoder())
}

/// Start a thread from a message, the thread has the message's id.
/// https://docs.discord.com/developers/resources/channel#start-thread-from-message
pub fn start_thread_request(
  base: request.Request(BitArray),
  channel: String,
  message: String,
  name: String,
) -> request.Request(BitArray) {
  let body = json.object([#("name", json.string(name))]) |> json.to_string
  base
  |> utils.set_method(http.Post)
  |> utils.append_path(
    "/channels/" <> channel <> "/messages/" <> message <> "/threads",
  )
  |> utils.set_body("application/json; charset=utf-8", <<body:utf8>>)
}

pub fn start_thread_response(
  response: response.Response(BitArray),
) -> Result(Result(Nil, Failure), json.DecodeError) {
  decode_response(response, decode.success(Nil))
}

/// The users that reacted with an emoji, the emoji is `name` or `name:id` for custom emoji.
/// https://docs.discord.com/developers/resources/message#get-reactions
pub fn reactions_request(
  base: request.Request(BitArray),
  channel: String,
  message: String,
  emoji: String,
) -> request.Request(BitArray) {
  base
  |> utils.set_method(http.Get)
  |> utils.append_path(
    "/channels/"
    <> channel
    <> "/messages/"
    <> message
    <> "/reactions/"
    <> uri.percent_encode(emoji),
  )
  |> request.set_query([#("limit", "100")])
}

pub fn reactions_response(
  response: response.Response(BitArray),
) -> Result(Result(List(schema.User), Failure), json.DecodeError) {
  decode_response(response, decode.list(schema.user_decoder()))
}

fn decode_response(
  response: response.Response(BitArray),
  decoder: decode.Decoder(a),
) -> Result(Result(a, Failure), json.DecodeError) {
  case response.status {
    200 | 201 -> json.parse_bits(response.body, decode.map(decoder, Ok))
    429 -> {
      let decoder = {
        use seconds <- decode.field(
          "retry_after",
          decode.one_of(decode.float, [decode.map(decode.int, int.to_float)]),
        )
        decode.success(Error(RateLimited(seconds)))
      }
      json.parse_bits(response.body, decoder)
    }
    400 | 401 | 403 | 404 ->
      json.parse_bits(
        response.body,
        schema.api_error_decoder()
          |> decode.map(fn(error) { Error(DiscordError(error)) }),
      )
    _ -> Ok(Error(UnexpectedStatus(response)))
  }
}
