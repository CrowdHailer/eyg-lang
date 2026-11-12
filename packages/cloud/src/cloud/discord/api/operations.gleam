import cloud/discord/api/pagination
import cloud/discord/api/schema
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
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

fn decode_response(
  response: response.Response(BitArray),
  decoder: decode.Decoder(a),
) -> Result(Result(a, Failure), json.DecodeError) {
  case response.status {
    200 -> json.parse_bits(response.body, decode.map(decoder, Ok))
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
