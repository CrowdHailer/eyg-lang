//// The events a session records, they are enough to resume the session.
////
//// Continuations are not saved, the code is saved and replayed with the recorded answers.
//// Reads and writes of files are not saved either, they are run again from the recorded roots.
//// Effects that are deterministic are run again, such as DecodeJSON or Hash.

import cloud/beam/execute
import eyg/ir/dag_json
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response, Response}
import gleam/json
import gleam/option.{type Option}
import multiformats/cid/v1

pub type Event {
  /// Code was sent to the session, it runs with the policy in the blob store under `policy`.
  Started(code: String, policy: v1.Cid)
  /// The code continued from this root in the box.
  /// The changes it made are in the root of the event that ends the segment.
  Resumed(root: v1.Cid)
  /// The answer to an effect, for Random, Now and Flip it is recorded when the code continues.
  /// The response to a fetch is recorded as soon as it is received.
  Answered(answer: execute.Answer)
  /// A reference to the latest release of a package resolved to this module,
  /// it resolves to the same module for the rest of the turn and when the turn is replayed.
  Pinned(package: String, version: Option(Int), module: v1.Cid)
  /// A secret was read. Only a fingerprint is recorded, so a change to the secret is noticed on replay.
  Read(name: String, fingerprint: String)
  /// A request is recorded before it is sent, with the root of the changes made before it.
  Requested(request: Request(BitArray), root: v1.Cid)
  /// Sleeping is recorded before it starts, with the root of the changes made before it.
  Slept(milliseconds: Int, root: v1.Cid)
  /// The code returned, with the root of its changes. They are merged before the turn finishes.
  Returned(outcome: Result(String, String), output: List(String), root: v1.Cid)
  /// The turn finished, `root` is where it left the files, the root it started from if its changes were rejected.
  Finished(outcome: Result(String, String), output: List(String), root: v1.Cid)
}

pub fn encode(event: Event) -> json.Json {
  json.object(fields(event))
}

/// The fields of the event's JSON object, so other fields can be added.
pub fn fields(event: Event) -> List(#(String, json.Json)) {
  case event {
    Started(code, policy) -> [
      #("type", json.string("started")),
      #("code", json.string(code)),
      #("policy", json.string(v1.to_string(policy))),
    ]
    Resumed(root) -> [#("type", json.string("resumed")), root_field(root)]
    Answered(answer) -> [
      #("type", json.string("answered")),
      ..case answer {
        execute.Number(number) -> [#("number", json.int(number))]
        execute.Flipped(value) -> [#("flipped", json.bool(value))]
        // Sleeping is recorded when it starts and secrets are only fingerprinted.
        execute.Slept | execute.Secret(_) -> []
        execute.Fetched(Ok(response)) -> [
          #("response", encode_response(response)),
        ]
        execute.Fetched(Error(reason)) -> [#("failed", json.string(reason))]
      }
    ]
    Pinned(package, version, module) -> [
      #("type", json.string("pinned")),
      #("package", json.string(package)),
      #("version", json.nullable(version, json.int)),
      #("module", json.string(v1.to_string(module))),
    ]
    Read(name, fingerprint) -> [
      #("type", json.string("read")),
      #("name", json.string(name)),
      #("fingerprint", json.string(fingerprint)),
    ]
    Requested(request, root) -> [
      #("type", json.string("requested")),
      #("request", encode_request(request)),
      root_field(root),
    ]
    Slept(milliseconds, root) -> [
      #("type", json.string("slept")),
      #("milliseconds", json.int(milliseconds)),
      root_field(root),
    ]
    Returned(outcome, output, root) -> [
      #("type", json.string("returned")),
      outcome_field(outcome),
      #("output", json.array(output, json.string)),
      root_field(root),
    ]
    Finished(outcome, output, root) -> [
      #("type", json.string("finished")),
      outcome_field(outcome),
      #("output", json.array(output, json.string)),
      root_field(root),
    ]
  }
}

pub fn decoder() -> decode.Decoder(Event) {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "started" -> {
      use code <- decode.field("code", decode.string)
      use policy <- decode.field("policy", cid_decoder())
      decode.success(Started(code, policy))
    }
    "resumed" -> {
      use root <- decode.field("root", cid_decoder())
      decode.success(Resumed(root))
    }
    "answered" -> decode.map(answer_decoder(), Answered)
    "pinned" -> {
      use package <- decode.field("package", decode.string)
      use version <- decode.field("version", decode.optional(decode.int))
      use module <- decode.field("module", cid_decoder())
      decode.success(Pinned(package, version, module))
    }
    "read" -> {
      use name <- decode.field("name", decode.string)
      use fingerprint <- decode.field("fingerprint", decode.string)
      decode.success(Read(name, fingerprint))
    }
    "requested" -> {
      use request <- decode.field("request", request_decoder())
      use root <- decode.field("root", cid_decoder())
      decode.success(Requested(request, root))
    }
    "slept" -> {
      use milliseconds <- decode.field("milliseconds", decode.int)
      use root <- decode.field("root", cid_decoder())
      decode.success(Slept(milliseconds, root))
    }
    "returned" -> {
      use outcome <- decode.then(outcome_decoder())
      use output <- decode.field("output", decode.list(decode.string))
      use root <- decode.field("root", cid_decoder())
      decode.success(Returned(outcome, output, root))
    }
    "finished" -> {
      use outcome <- decode.then(outcome_decoder())
      use output <- decode.field("output", decode.list(decode.string))
      use root <- decode.field("root", cid_decoder())
      decode.success(Finished(outcome, output, root))
    }
    _ -> decode.failure(Resumed(dag_json.vacant_cid), "Event")
  }
}

fn answer_decoder() {
  decode.one_of(
    decode.at(["number"], decode.int) |> decode.map(execute.Number),
    [
      decode.at(["flipped"], decode.bool) |> decode.map(execute.Flipped),
      decode.at(["response"], response_decoder())
        |> decode.map(fn(response) { execute.Fetched(Ok(response)) }),
      decode.at(["failed"], decode.string)
        |> decode.map(fn(reason) { execute.Fetched(Error(reason)) }),
    ],
  )
}

fn outcome_field(outcome) {
  case outcome {
    Ok(value) -> #("value", json.string(value))
    Error(reason) -> #("error", json.string(reason))
  }
}

fn outcome_decoder() {
  decode.one_of(decode.at(["value"], decode.string) |> decode.map(Ok), [
    decode.at(["error"], decode.string) |> decode.map(Error),
  ])
}

fn root_field(root) {
  #("root", json.string(v1.to_string(root)))
}

fn cid_decoder() {
  use encoded <- decode.then(decode.string)
  case v1.from_string(encoded) {
    Ok(#(cid, _)) -> decode.success(cid)
    Error(_) -> decode.failure(dag_json.vacant_cid, "CID")
  }
}

fn encode_request(request: Request(BitArray)) {
  json.object([
    #("method", json.string(http.method_to_string(request.method))),
    #("scheme", json.string(http.scheme_to_string(request.scheme))),
    #("host", json.string(request.host)),
    #("port", json.nullable(request.port, json.int)),
    #("path", json.string(request.path)),
    #("query", json.nullable(request.query, json.string)),
    #("headers", encode_headers(request.headers)),
    #("body", json.string(bit_array.base64_encode(request.body, True))),
  ])
}

fn request_decoder() {
  use method <- decode.field("method", {
    use method <- decode.then(decode.string)
    case http.parse_method(method) {
      Ok(method) -> decode.success(method)
      Error(Nil) -> decode.failure(http.Get, "Method")
    }
  })
  use scheme <- decode.field("scheme", {
    use scheme <- decode.then(decode.string)
    case http.scheme_from_string(scheme) {
      Ok(scheme) -> decode.success(scheme)
      Error(Nil) -> decode.failure(http.Https, "Scheme")
    }
  })
  use host <- decode.field("host", decode.string)
  use port <- decode.field("port", decode.optional(decode.int))
  use path <- decode.field("path", decode.string)
  use query <- decode.field("query", decode.optional(decode.string))
  use headers <- decode.field("headers", headers_decoder())
  use body <- decode.field("body", body_decoder())
  decode.success(Request(
    method:,
    headers:,
    body:,
    scheme:,
    host:,
    port:,
    path:,
    query:,
  ))
}

fn encode_response(response: Response(BitArray)) {
  json.object([
    #("status", json.int(response.status)),
    #("headers", encode_headers(response.headers)),
    #("body", json.string(bit_array.base64_encode(response.body, True))),
  ])
}

fn response_decoder() {
  use status <- decode.field("status", decode.int)
  use headers <- decode.field("headers", headers_decoder())
  use body <- decode.field("body", body_decoder())
  decode.success(Response(status:, headers:, body:))
}

fn encode_headers(headers) {
  json.array(headers, fn(header: #(String, String)) {
    json.preprocessed_array([json.string(header.0), json.string(header.1)])
  })
}

fn headers_decoder() {
  decode.list({
    use name <- decode.field(0, decode.string)
    use value <- decode.field(1, decode.string)
    decode.success(#(name, value))
  })
}

fn body_decoder() {
  use encoded <- decode.then(decode.string)
  case bit_array.base64_decode(encoded) {
    Ok(body) -> decode.success(body)
    Error(Nil) -> decode.failure(<<>>, "Base64")
  }
}
