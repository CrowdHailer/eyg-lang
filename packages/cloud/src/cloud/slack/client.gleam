import cloud/slack/operations
import cloud/slack/schema
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option.{None, Some}
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

/// Fetch every page of public and accessible private workspace channels.
pub fn conversations_list(
  context: Context(t),
) -> K(t, Result(List(schema.Channel), Failure)) {
  list_channels(context, None, [])
}

fn list_channels(
  context: Context(t),
  cursor: option.Option(String),
  acc: List(schema.Channel),
) -> K(t, Result(List(schema.Channel), Failure)) {
  let request =
    operations.conversations_list_request(
      base_request(context.token),
      cursor: cursor,
    )
  use response <- continuation.then(context.fetch(request))
  case response {
    Ok(response) ->
      case operations.conversations_list_response(response) {
        Ok(Ok(page)) -> {
          let acc =
            list.fold(page.channels, acc, fn(acc, channel) { [channel, ..acc] })
          case page.next_cursor {
            "" -> continuation.done(list.reverse(acc))
            cursor -> list_channels(context, Some(cursor), acc)
          }
        }
        Ok(Error(reason)) -> continuation.fail(ApiFailure(reason))
        Error(reason) -> continuation.fail(InvalidResponse(reason))
      }
    Error(reason) -> continuation.fail(RequestFailed(reason))
  }
}
