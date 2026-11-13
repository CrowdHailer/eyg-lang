//// Real implementations of effects require by continuation based code such as clients.

import envoy
import gleam/crypto
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/option
import midas/continuation.{type Continuation as K}
import midas/effect
import ogre/origin

pub fn fetch(
  request: request.Request(BitArray),
) -> K(t, Result(response.Response(BitArray), effect.FetchError)) {
  // Model completions can take minutes.
  case
    httpc.configure() |> httpc.timeout(300_000) |> httpc.dispatch_bits(request)
  {
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

/// Send outbound https requests through the proxy named by `HTTPS_PROXY`.
/// Erlang's httpc does not read proxy environment variables itself.
pub fn configure_proxy() -> Nil {
  case envoy.get("HTTPS_PROXY") {
    Ok(proxy) ->
      case origin.from_string_strict(proxy) {
        Ok(origin.Origin(host:, port: option.Some(port), ..)) ->
          set_https_proxy(host, port)
        _ -> Nil
      }
    Error(Nil) -> Nil
  }
}

@external(erlang, "cloud_ffi", "set_https_proxy")
fn set_https_proxy(host: String, port: Int) -> Nil
