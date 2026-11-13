import cloud/discord/api/operations
import cloud/discord/api/pagination
import cloud/discord/api/schema
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option
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
  NonAdvancingCursor
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

pub fn create_message(
  context: Context(t),
  channel: String,
  message: String,
  text: String,
) -> K(t, Result(Nil, Failure)) {
  let request =
    operations.create_message_request(
      base_request(context.token),
      channel,
      message,
      text,
    )
  use response <- continuation.map(context.fetch(request))
  case response {
    Ok(response) ->
      case operations.create_message_response(response) {
        Ok(Ok(Nil)) -> Ok(Nil)
        Ok(Error(reason)) -> Error(ApiFailure(reason))
        Error(reason) -> Error(InvalidResponse(reason))
      }
    Error(reason) -> Error(RequestFailed(reason))
  }
}

pub fn guild(
  context: Context(t),
  guild: String,
) -> K(t, Result(schema.Guild, Failure)) {
  let request = operations.guild_request(base_request(context.token), guild)
  use response <- continuation.map(context.fetch(request))
  case response {
    Ok(response) ->
      case operations.guild_response(response) {
        Ok(Ok(guild)) -> Ok(guild)
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

/// Fetch all available history, newest-first. Threads use their own channel ID.
pub fn channel_messages(
  context: Context(t),
  channel: String,
) -> K(t, Result(List(schema.Message), Failure)) {
  channel_messages_since(context, channel, option.None)
}

/// Fetch every page newer than `after`, excluding the boundary message.
pub fn channel_messages_since(
  context: Context(t),
  channel: String,
  after: option.Option(String),
) -> K(t, Result(List(schema.Message), Failure)) {
  use pages <- continuation.try_then(pagination.fetch_all(
    history_page(context, channel, _),
    after,
  ))
  // `after` pages move forwards, but each page is newest-first.
  continuation.done(pages |> list.reverse |> list.flatten)
}

fn history_page(
  context: Context(t),
  channel: String,
  cursor: option.Option(String),
) -> K(t, Result(pagination.Page(List(schema.Message)), Failure)) {
  let after = option.unwrap(cursor, "0")
  let request =
    operations.channel_messages_request(
      base_request(context.token),
      channel,
      after: after,
    )
  use response <- continuation.map(context.fetch(request))
  case response {
    Ok(response) ->
      case operations.channel_messages_response(response) {
        Ok(Ok(page)) ->
          case page.next_cursor == option.Some(after) {
            True -> Error(NonAdvancingCursor)
            False -> Ok(page)
          }
        Ok(Error(reason)) -> Error(ApiFailure(reason))
        Error(reason) -> Error(InvalidResponse(reason))
      }
    Error(reason) -> Error(RequestFailed(reason))
  }
}

fn call(
  context: Context(t),
  request: request.Request(BitArray),
  decode: fn(response.Response(BitArray)) ->
    Result(Result(a, operations.Failure), json.DecodeError),
) -> K(t, Result(a, Failure)) {
  use response <- continuation.map(context.fetch(request))
  case response {
    Ok(response) ->
      case decode(response) {
        Ok(Ok(value)) -> Ok(value)
        Ok(Error(reason)) -> Error(ApiFailure(reason))
        Error(reason) -> Error(InvalidResponse(reason))
      }
    Error(reason) -> Error(RequestFailed(reason))
  }
}

/// Post a message and return its id.
pub fn post_message(
  context: Context(t),
  channel: String,
  text: String,
) -> K(t, Result(String, Failure)) {
  base_request(context.token)
  |> operations.post_message_request(channel, text)
  |> call(context, _, operations.post_message_response)
}

pub fn recent_messages(
  context: Context(t),
  channel: String,
  limit: Int,
) -> K(t, Result(List(schema.Post), Failure)) {
  base_request(context.token)
  |> operations.recent_messages_request(channel, limit)
  |> call(context, _, operations.recent_messages_response)
}

pub fn get_message(
  context: Context(t),
  channel: String,
  message: String,
) -> K(t, Result(schema.Post, Failure)) {
  base_request(context.token)
  |> operations.get_message_request(channel, message)
  |> call(context, _, operations.get_message_response)
}

pub fn active_threads(
  context: Context(t),
  guild: String,
) -> K(t, Result(List(schema.Thread), Failure)) {
  base_request(context.token)
  |> operations.active_threads_request(guild)
  |> call(context, _, operations.active_threads_response)
}

pub fn start_thread(
  context: Context(t),
  channel: String,
  message: String,
  name: String,
) -> K(t, Result(Nil, Failure)) {
  base_request(context.token)
  |> operations.start_thread_request(channel, message, name)
  |> call(context, _, operations.start_thread_response)
}

pub fn reactions(
  context: Context(t),
  channel: String,
  message: String,
  emoji: String,
) -> K(t, Result(List(schema.User), Failure)) {
  base_request(context.token)
  |> operations.reactions_request(channel, message, emoji)
  |> call(context, _, operations.reactions_response)
}
