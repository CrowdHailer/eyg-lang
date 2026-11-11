//// Real implementations of effects require by continuation based code such as clients.

import gleam/http/request
import gleam/http/response
import gleam/httpc
import midas/continuation.{type Continuation as K}
import midas/effect

pub fn fetch(
  request: request.Request(BitArray),
) -> K(t, Result(response.Response(BitArray), effect.FetchError)) {
  case httpc.send_bits(request) {
    Ok(response) -> continuation.done(response)
    Error(httpc.InvalidUtf8Response) ->
      continuation.fail(effect.UnableToReadBody)
    Error(httpc.FailedToConnect(..)) ->
      continuation.fail(effect.NetworkError("Failed to connect"))
    Error(httpc.ResponseTimeout) ->
      continuation.fail(effect.NetworkError("response timeout"))
  }
}
