//// Record the model's side of a session and replay it.
////
//// A cassette holds each request's key with the response the model streamed.
//// Replaying a cassette gives the same completions without the model, so a
//// run can be graded again and harness changes can be checked in CI.
////
//// A replayed request that differs from the recorded one means the session
//// changed: the prompt, the context or a result sent back to the model. Strict
//// replay fails there, lenient replay carries on and returns the recording.

import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/fetch
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{Response}
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/string
import gleam/uri
import javascript/mutable_reference.{type MutableReference}
import overlay/eval/model.{type Transport}

pub type Cassette {
  Cassette(interactions: List(Interaction))
}

pub type Interaction {
  // Responses are stored whole, how they were chunked does not matter.
  Interaction(key: String, status: Int, body: BitArray)
}

/// Stable request identity, including protocol headers but excluding credentials
/// and the time-dependent parts of a SigV4 signature.
pub fn key(request: Request(BitArray)) -> String {
  let url = request.to_uri(request) |> uri.to_string
  let method = http.method_to_string(request.method)
  let headers =
    request.headers
    |> list.map(fn(header) {
      #(string.lowercase(header.0), string.trim(header.1))
    })
    |> list.filter(fn(header) {
      !list.contains(
        [
          "authorization",
          "cookie",
          "x-api-key",
          "api-key",
          "x-amz-date",
          "x-amz-security-token",
        ],
        header.0,
      )
    })
    |> list.sort(fn(a, b) {
      case string.compare(a.0, b.0) {
        order.Eq -> string.compare(a.1, b.1)
        ordering -> ordering
      }
    })
    |> list.map(fn(header) {
      json.object([
        #("name", json.string(header.0)),
        #("value", json.string(header.1)),
      ])
    })
    |> json.preprocessed_array
    |> json.to_string
  "v2:"
  <> hash(<<
    method:utf8,
    " ":utf8,
    url:utf8,
    "\n":utf8,
    headers:utf8,
    "\n":utf8,
    request.body:bits,
  >>)
}

fn hash(bytes) {
  bytes
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base16_encode
  |> string.lowercase
}

/// Compatibility with source-branch cassettes that predate protocol-header keys.
fn legacy_key(request) {
  let url = request.to_uri(request) |> uri.to_string
  let method = http.method_to_string(request.method)
  hash(<<method:utf8, " ":utf8, url:utf8, "\n":utf8, request.body:bits>>)
}

pub opaque type Recorder {
  Recorder(interactions: MutableReference(List(Interaction)))
}

pub fn recorder() -> Recorder {
  Recorder(mutable_reference.new([]))
}

/// Send requests with another transport, keeping every exchange.
pub fn record(transport: Transport, recorder: Recorder) -> Transport {
  fn(request) {
    let key = key(request)
    use result <- promise.map(transport(request))
    case result {
      Ok(Response(status:, headers:, body: reader)) -> {
        let chunks = mutable_reference.new([])
        let reader = fn() {
          use chunk <- promise.map(reader())
          case chunk {
            Ok(Some(bytes)) -> {
              let _ =
                mutable_reference.set(chunks, [
                  bytes,
                  ..mutable_reference.get(chunks)
                ])
              Nil
            }
            Ok(None) -> {
              let body =
                bit_array.concat(list.reverse(mutable_reference.get(chunks)))
              let interaction = Interaction(key:, status:, body:)
              let _ =
                mutable_reference.set(recorder.interactions, [
                  interaction,
                  ..mutable_reference.get(recorder.interactions)
                ])
              Nil
            }
            // An incomplete stream must not replay as a successful response.
            // Replay will fail at this request because no response was recorded.
            Error(_) -> Nil
          }
          chunk
        }
        Ok(Response(status:, headers:, body: reader))
      }
      Error(reason) -> Error(reason)
    }
  }
}

/// Everything recorded so far, in order.
pub fn recorded(recorder: Recorder) -> Cassette {
  Cassette(list.reverse(mutable_reference.get(recorder.interactions)))
}

pub type Matching {
  // A request that differs from the recording fails.
  Strict
  // Recordings are returned in order whatever was requested.
  Lenient
}

/// Answer requests from a cassette, in the order they were recorded.
pub fn replay(cassette: Cassette, matching: Matching) -> Transport {
  let remaining = mutable_reference.new(#(0, cassette.interactions))
  fn(request) {
    let #(index, interactions) = mutable_reference.get(remaining)
    case interactions {
      [] ->
        Error(fetch.NetworkError(
          "the cassette has no response for request "
          <> int.to_string(index + 1),
        ))
      [Interaction(key: recorded, status:, body:), ..rest] -> {
        let _ = mutable_reference.set(remaining, #(index + 1, rest))
        let matches = case string.starts_with(recorded, "v2:") {
          True -> recorded == key(request)
          False -> recorded == legacy_key(request)
        }
        case matching, matches {
          Strict, False ->
            Error(fetch.NetworkError(
              "request "
              <> int.to_string(index + 1)
              <> " differs from the recording, the session has changed",
            ))
          _, _ -> {
            let chunks = mutable_reference.new([body])
            let reader = fn() {
              case mutable_reference.get(chunks) {
                [chunk, ..rest] -> {
                  let _ = mutable_reference.set(chunks, rest)
                  Ok(Some(chunk))
                }
                [] -> Ok(None)
              }
              |> promise.resolve
            }
            Ok(Response(status:, headers: [], body: reader))
          }
        }
      }
    }
    |> promise.resolve
  }
}

pub fn encode(cassette: Cassette) -> json.Json {
  json.object([
    #(
      "interactions",
      json.array(cassette.interactions, fn(interaction) {
        let Interaction(key:, status:, body:) = interaction
        let body = case bit_array.to_string(body) {
          Ok(text) -> [#("body", json.string(text))]
          Error(Nil) -> [
            #("base64", json.string(bit_array.base64_encode(body, True))),
          ]
        }
        json.object([
          #("key", json.string(key)),
          #("status", json.int(status)),
          ..body
        ])
      }),
    ),
  ])
}

pub fn decoder() -> decode.Decoder(Cassette) {
  let interaction = {
    use key <- decode.field("key", decode.string)
    use status <- decode.field("status", decode.int)
    use body <- decode.then(
      decode.one_of(
        decode.at(["body"], decode.map(decode.string, bit_array.from_string)),
        [
          decode.at(["base64"], decode.string)
          |> decode.then(fn(encoded) {
            case bit_array.base64_decode(encoded) {
              Ok(bytes) -> decode.success(bytes)
              Error(Nil) -> decode.failure(<<>>, "base64")
            }
          }),
        ],
      ),
    )
    decode.success(Interaction(key:, status:, body:))
  }
  use interactions <- decode.field("interactions", decode.list(interaction))
  decode.success(Cassette(interactions:))
}
