//// Real implementations of effects require by continuation based code such as clients.

import gleam/crypto
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

pub fn hash(algorithm: effect.HashAlgorithm, bytes) {
  let algorithm = case algorithm {
    effect.Sha1 -> crypto.Sha1
    effect.Sha256 -> crypto.Sha256
    effect.Sha384 -> crypto.Sha384
    effect.Sha512 -> crypto.Sha512
  }
  continuation.return(crypto.hash(algorithm, bytes))
}
