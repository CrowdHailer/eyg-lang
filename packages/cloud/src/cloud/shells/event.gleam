//// The entries of a shell's journal, they are enough to resume the shell.
////
//// Code runs in segments: from an input until it finishes, makes a request or sleeps.
//// An input is what a segment runs with and the box event it starts from, an output is what the segment did.
//// Continuations are not saved, the code is saved and replayed with the recorded answers.
//// Reads and writes of files are not saved either, they are run again from the recorded roots.
//// Effects that are deterministic are run again, such as DecodeJSON or Hash.

import cloud/beam/execute
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response, Response}
import gleam/json
import gleam/option.{type Option}
import multiformats/cid/v1

pub type Entry {
  /// What the next segment runs with. It runs from the box event `start`, where the box's root is `root`.
  Input(trigger: Trigger, start: Int, root: v1.Cid)
  /// What a segment did. `root` has the changes the code made, they were merged into the box as `change` says.
  Output(answers: List(Answer), stop: Stop, root: v1.Cid, change: Change)
}

/// What starts a segment.
pub type Trigger {
  /// Code was sent to the shell, it runs with the policy in the blob store under `policy`.
  Started(code: String, policy: v1.Cid)
  /// A program built in a structural editor was sent to the shell, it runs as code does.
  Submitted(program: ir.Node(Nil), policy: v1.Cid)
  /// The answer to the request or sleep the last segment stopped at,
  /// or the rejection of its change, when the box did not accept it.
  Continued(answer: execute.Answer)
}

/// An answer given to the code while a segment ran.
pub type Answer {
  /// The answer to an effect such as Random or Now.
  Answered(answer: execute.Answer)
  /// A reference to the latest release of a package resolved to this module,
  /// it resolves to the same module for the rest of the turn and when the turn is replayed.
  Pinned(package: String, version: Option(Int), module: v1.Cid)
  /// A secret was read. Only a fingerprint is recorded, so a change to the secret is noticed on replay.
  Read(name: String, fingerprint: String)
}

/// Where a segment stopped.
pub type Stop {
  /// A request is recorded before it is sent.
  Requested(request: Request(BitArray))
  /// Sleeping is recorded before it starts.
  Slept(milliseconds: Int)
  /// The code returned, ending the turn.
  Finished(outcome: Result(String, String), output: List(String))
}

/// What became of the changes a segment made.
pub type Change {
  /// The code changed no files.
  Unchanged
  /// The changes were merged into the box, in the same transaction as the output was recorded.
  Merged
  /// The box did not accept the changes, the code continues without them.
  Rejected(reason: String)
}

/// Whether the trigger starts a turn.
pub fn starts(trigger: Trigger) -> Bool {
  case trigger {
    Started(..) | Submitted(..) -> True
    Continued(_) -> False
  }
}

pub fn encode(entry: Entry) -> json.Json {
  json.object(fields(entry))
}

/// The entry as it is stored in the journal, the start of an input is stored alongside it, not in it.
pub fn stored(entry: Entry) -> String {
  case entry {
    Input(trigger, ..) ->
      json.object([#("type", json.string("input")), ..trigger_fields(trigger)])
    Output(..) -> encode(entry)
  }
  |> json.to_string
}

/// The fields of the entry's JSON object, so other fields can be added.
/// The start of an input is recorded alongside the entry, its root is only included here.
pub fn fields(entry: Entry) -> List(#(String, json.Json)) {
  case entry {
    Input(trigger, start, root) -> [
      #("type", json.string("input")),
      #("start", json.int(start)),
      root_field(root),
      ..trigger_fields(trigger)
    ]
    Output(answers, stop, root, change) -> [
      #("type", json.string("output")),
      #(
        "answers",
        json.array(answers, fn(answer) { json.object(answer_fields(answer)) }),
      ),
      #("stop", json.object(stop_fields(stop))),
      root_field(root),
      #("change", change_json(change)),
    ]
  }
}

fn trigger_fields(trigger) {
  case trigger {
    Started(code, policy) -> [
      #("trigger", json.string("started")),
      #("code", json.string(code)),
      #("policy", json.string(v1.to_string(policy))),
    ]
    Submitted(program, policy) -> [
      #("trigger", json.string("submitted")),
      #("program", dag_json.to_data_model(program)),
      #("policy", json.string(v1.to_string(policy))),
    ]
    Continued(answer) -> [
      #("trigger", json.string("continued")),
      ..encode_answer(answer)
    ]
  }
}

fn answer_fields(answer) {
  case answer {
    Answered(answer) -> [
      #("type", json.string("answered")),
      ..encode_answer(answer)
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
  }
}

fn encode_answer(answer) {
  case answer {
    execute.Number(number) -> [#("number", json.int(number))]
    execute.Flipped(value) -> [#("flipped", json.bool(value))]
    execute.Slept -> [#("woke", json.bool(True))]
    // Secrets are only fingerprinted.
    execute.Secret(_) -> []
    execute.Fetched(Ok(response)) -> [#("response", encode_response(response))]
    execute.Fetched(Error(reason)) -> [#("failed", json.string(reason))]
    execute.Rejected(reason) -> [#("rejected", json.string(reason))]
  }
}

fn stop_fields(stop) {
  case stop {
    Requested(request) -> [
      #("type", json.string("requested")),
      #("request", encode_request(request)),
    ]
    Slept(milliseconds) -> [
      #("type", json.string("slept")),
      #("milliseconds", json.int(milliseconds)),
    ]
    Finished(outcome, output) -> [
      #("type", json.string("finished")),
      outcome_field(outcome),
      #("output", json.array(output, json.string)),
    ]
  }
}

fn change_json(change) {
  case change {
    Unchanged -> json.object([#("type", json.string("unchanged"))])
    Merged -> json.object([#("type", json.string("merged"))])
    Rejected(reason) ->
      json.object([
        #("type", json.string("rejected")),
        #("reason", json.string(reason)),
      ])
  }
}

/// Decode an entry as it is stored, an input is given the start recorded alongside it and the root there.
pub fn decoder(start: Option(#(Int, v1.Cid))) -> decode.Decoder(Entry) {
  use type_ <- decode.field("type", decode.string)
  case type_, start {
    "input", option.Some(#(start, root)) -> {
      use trigger <- decode.then(trigger_decoder())
      decode.success(Input(trigger, start, root))
    }
    "output", _ -> {
      use answers <- decode.field(
        "answers",
        decode.list(entry_answer_decoder()),
      )
      use stop <- decode.field("stop", stop_decoder())
      use root <- decode.field("root", cid_decoder())
      use change <- decode.field("change", change_decoder())
      decode.success(Output(answers, stop, root, change))
    }
    _, _ ->
      decode.failure(
        Input(Continued(execute.Slept), 0, dag_json.vacant_cid),
        "Journal entry",
      )
  }
}

fn trigger_decoder() {
  use trigger <- decode.field("trigger", decode.string)
  case trigger {
    "started" -> {
      use code <- decode.field("code", decode.string)
      use policy <- decode.field("policy", cid_decoder())
      decode.success(Started(code, policy))
    }
    "submitted" -> {
      use program <- decode.field("program", dag_json.decoder(Nil))
      use policy <- decode.field("policy", cid_decoder())
      decode.success(Submitted(program, policy))
    }
    "continued" -> decode.map(answer_decoder(), Continued)
    _ -> decode.failure(Continued(execute.Slept), "Trigger")
  }
}

fn entry_answer_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
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
    _ -> decode.failure(Read("", ""), "Answer")
  }
}

fn stop_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "requested" -> {
      use request <- decode.field("request", request_decoder())
      decode.success(Requested(request))
    }
    "slept" -> {
      use milliseconds <- decode.field("milliseconds", decode.int)
      decode.success(Slept(milliseconds))
    }
    "finished" -> {
      use outcome <- decode.then(outcome_decoder())
      use output <- decode.field("output", decode.list(decode.string))
      decode.success(Finished(outcome, output))
    }
    _ -> decode.failure(Slept(0), "Stop")
  }
}

fn change_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "unchanged" -> decode.success(Unchanged)
    "merged" -> decode.success(Merged)
    "rejected" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(Rejected(reason))
    }
    _ -> decode.failure(Unchanged, "Change")
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
      decode.at(["rejected"], decode.string) |> decode.map(execute.Rejected),
      decode.at(["woke"], decode.bool) |> decode.map(fn(_) { execute.Slept }),
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
