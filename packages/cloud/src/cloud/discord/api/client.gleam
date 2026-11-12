import cloud/discord/api/operations
import cloud/discord/api/schema
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import midas/continuation.{type Continuation as K}
import midas/effect

pub fn base_request(token: String) -> request.Request(BitArray) {
  request.new()
  |> request.set_scheme(http.Https)
  |> request.set_host("discord.com")
  |> request.set_path("/api/v10")
  |> request.set_header("authorization", "Bot " <> token)
  |> request.set_body(<<>>)
}

pub type Context(t) {
  Context(token: String, fetch: effect.Fetch(t))
}

pub type Failure {
  RequestFailed(effect.FetchError)
  InvalidResponse(json.DecodeError)
  ApiFailure(operations.Failure)
}

pub fn current_user(
  context: Context(t),
) -> K(t, Result(schema.Identity, Failure)) {
  let request = operations.current_user_request(base_request(context.token))
  use response <- continuation.map(context.fetch(request))
  case response {
    Ok(response) ->
      case operations.current_user_response(response) {
        Ok(Ok(identity)) -> Ok(identity)
        Ok(Error(reason)) -> Error(ApiFailure(reason))
        Error(reason) -> Error(InvalidResponse(reason))
      }
    Error(reason) -> Error(RequestFailed(reason))
  }
}

/// Discover text and announcement channels in a guild (server).
pub fn guild_channels(
  context: Context(t),
  guild: String,
) -> K(t, Result(List(schema.Channel), Failure)) {
  let request =
    operations.guild_channels_request(base_request(context.token), guild)
  use response <- continuation.map(context.fetch(request))
  case response {
    Ok(response) ->
      case operations.guild_channels_response(response) {
        Ok(Ok(channels)) ->
          Ok(
            list.filter(channels, fn(channel) {
              // TODO parse this better and return an enum of channel kinds
              channel.kind == 0 || channel.kind == 5
            }),
          )
        Ok(Error(reason)) -> Error(ApiFailure(reason))
        Error(reason) -> Error(InvalidResponse(reason))
      }
    Error(reason) -> Error(RequestFailed(reason))
  }
}
