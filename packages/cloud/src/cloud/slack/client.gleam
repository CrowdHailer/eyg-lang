import cloud/slack/operations
import cloud/slack/pagination
import cloud/slack/schema
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import midas/continuation.{type Continuation as K}
import midas/effect

pub fn base_request(token: String) -> request.Request(BitArray) {
  request.new()
  |> request.set_scheme(http.Https)
  |> request.set_host("slack.com")
  |> request.set_path("/api")
  |> request.set_header("authorization", "Bearer " <> token)
  |> request.set_body(<<>>)
}

pub type Context(t) {
  Context(token: String, fetch: effect.Fetch(t))
}

/// This Failure type wraps the operations concept of failure
pub type Failure {
  RequestFailed(effect.FetchError)
  InvalidResponse(json.DecodeError)
  ApiFailure(operations.Failure)
}

pub fn auth_test(
  context: Context(t),
) -> K(t, Result(schema.Identity, Failure)) {
  let request = operations.auth_test_request(base_request(context.token))
  use response <- continuation.map(context.fetch(request))
  case response {
    Ok(response) ->
      case operations.auth_test_response(response) {
        Ok(Ok(identity)) -> Ok(identity)
        Ok(Error(reason)) -> Error(ApiFailure(reason))
        Error(reason) -> Error(InvalidResponse(reason))
      }
    Error(reason) -> Error(RequestFailed(reason))
  }
}

/// Fetch every page of public workspace channels.
pub fn conversations_list(
  context: Context(t),
) -> K(t, Result(List(schema.Channel), Failure)) {
  pagination.fetch_all(channels_page(context, _))
  |> continuation.map(result.map(_, list.flatten))
}

fn channels_page(
  context: Context(t),
  cursor: option.Option(String),
) -> K(t, Result(pagination.Page(List(schema.Channel)), Failure)) {
  let request =
    operations.conversations_list_request(
      base_request(context.token),
      cursor: cursor,
    )
  use response <- continuation.map(context.fetch(request))
  case response {
    Ok(response) ->
      case operations.conversations_list_response(response) {
        Ok(Ok(page)) -> Ok(page)
        Ok(Error(reason)) -> Error(ApiFailure(reason))
        Error(reason) -> Error(InvalidResponse(reason))
      }
    Error(reason) -> Error(RequestFailed(reason))
  }
}

/// Fetch every page of available channel history (thread replies are separate).
pub fn conversations_history(
  context: Context(t),
  channel: String,
) -> K(t, Result(List(schema.Message), Failure)) {
  use pages <- continuation.try_then(
    pagination.fetch_all(history_page(context, channel, _)),
  )
  continuation.done(list.flat_map(pages, fn(page) { page.messages }))
}

fn history_page(
  context: Context(t),
  channel: String,
  cursor: option.Option(String),
) -> K(t, Result(pagination.Page(schema.History), Failure)) {
  let request =
    operations.conversations_history_request(
      base_request(context.token),
      channel,
      oldest: None,
      latest: None,
      cursor: cursor,
      limit: Some(100),
      inclusive: None,
    )
  use response <- continuation.map(context.fetch(request))
  case response {
    Ok(response) ->
      case operations.conversations_history_response(response) {
        Ok(Ok(page)) -> Ok(page)
        Ok(Error(reason)) -> Error(ApiFailure(reason))
        Error(reason) -> Error(InvalidResponse(reason))
      }
    Error(reason) -> Error(RequestFailed(reason))
  }
}
