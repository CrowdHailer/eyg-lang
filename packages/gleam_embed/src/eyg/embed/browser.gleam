//// The platform functions a JavaScript host passes to the libraries that need
//// them, such as `eyg_hub`'s cache, in the shape of `midas/effect`.

import gleam/fetch
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/javascript/promise.{type Promise}
import gleam/result
import gleam/string
import midas/effect
import plinth/browser/crypto/subtle

/// Send a request and read the whole body.
pub fn send(
  request: Request(BitArray),
) -> Promise(Result(Response(BitArray), effect.FetchError)) {
  use response <- promise.map(
    fetch.send_bits(request) |> promise.try_await(fetch.read_bytes_body),
  )
  result.map_error(response, fn(reason) {
    case reason {
      fetch.NetworkError(message) -> effect.NetworkError(message)
      fetch.UnableToReadBody | fetch.InvalidJsonBody -> effect.UnableToReadBody
    }
  })
}

/// `effect.Fetch` for a host that works with promises.
pub fn fetch(
  request: Request(BitArray),
) -> fn(fn(Result(Response(BitArray), effect.FetchError)) -> Promise(a)) ->
  Promise(a) {
  fn(resume) { promise.await(send(request), resume) }
}

/// `effect.Hash` using the platform's `crypto.subtle`.
pub fn hash(
  algorithm: effect.HashAlgorithm,
  bytes: BitArray,
) -> fn(fn(BitArray) -> Promise(a)) -> Promise(a) {
  fn(resume) { promise.await(digest(algorithm_name(algorithm), bytes), resume) }
}

fn algorithm_name(algorithm) {
  case algorithm {
    effect.Sha1 -> subtle.SHA1
    effect.Sha256 -> subtle.SHA256
    effect.Sha384 -> subtle.SHA384
    effect.Sha512 -> subtle.SHA512
  }
}

fn digest(algorithm, bytes) -> Promise(BitArray) {
  use result <- promise.map(subtle.digest(algorithm, bytes))
  let assert Ok(bytes) = result
  bytes
}

/// A readable description of a failed request.
pub fn describe(reason: effect.FetchError) -> String {
  case reason {
    effect.NetworkError(message) -> message
    other -> string.inspect(other)
  }
}
