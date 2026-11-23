//// OpenTelemetry spans for a shell, made from its journal.
////
//// The shell is one span, each turn is a span in it and each request is a span in its turn.
//// A request span starts when the request is recorded and ends when its response is recorded.
//// Spans are encoded as OTLP JSON, which can be posted to any OpenTelemetry collector.

import cloud/beam/execute
import cloud/shells/event.{type Entry}
import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri
import multiformats/cid/v1

pub type Span {
  Span(
    id: String,
    parent: Option(String),
    name: String,
    // A span for a request to another service.
    client: Bool,
    start: Int,
    end: Int,
    attributes: List(#(String, String)),
    error: Option(String),
  )
}

/// `log` is every entry of the shell's journal with the time it was recorded, in microseconds.
pub fn spans(shell: String, log: List(#(Int, Entry))) -> List(Span) {
  // Spans are numbered by their first entry.
  let log = list.index_map(log, fn(entry, i) { #(i, entry.0, entry.1) })
  case log, list.last(log) {
    [#(_, start, _), ..], Ok(#(_, end, _)) -> {
      let id = span_id(shell, -1)
      let attributes = [#("shell.id", shell)]
      let root = Span(id, None, "shell", False, start, end, attributes, None)
      [root, ..list.flat_map(turns(log), turn_spans(shell, id, _))]
    }
    _, _ -> []
  }
}

fn turns(log) {
  case log {
    [] -> []
    [#(i, at, event.Input(event.Started(code, policy), ..)), ..log] ->
      turn(i, at, #("eyg.code", code), policy, log)
    [_, ..log] -> turns(log)
  }
}

fn turn(i, at, input, policy, log: List(#(Int, Int, Entry))) {
  let #(entries, log) =
    list.split_while(log, fn(entry) {
      case entry.2 {
        event.Input(trigger, ..) -> !event.starts(trigger)
        _ -> True
      }
    })
  [#(i, at, input, policy, entries), ..turns(log)]
}

fn turn_spans(shell, parent, turn) {
  let #(i, start, input, policy, entries) = turn
  let id = span_id(shell, i)
  let finished =
    list.find_map(entries, fn(entry) {
      case entry {
        #(_, at, event.Output(change: event.Rejected(reason), ..)) ->
          Ok(#(at, Error(reason)))
        #(_, at, event.Output(stop: event.Finished(outcome, _), ..)) ->
          Ok(#(at, outcome))
        _ -> Error(Nil)
      }
    })
  let #(end, error) = case finished, list.last(entries) {
    Ok(#(at, Ok(_))), _ -> #(at, None)
    Ok(#(at, Error(reason))), _ -> #(at, Some(reason))
    Error(Nil), Ok(#(_, at, _)) -> #(at, Some("unfinished"))
    Error(Nil), Error(Nil) -> #(start, Some("unfinished"))
  }
  let attributes = [input, #("eyg.policy", v1.to_string(policy))]
  [
    Span(id, Some(parent), "turn", False, start, end, attributes, error),
    ..requests(shell, id, entries)
  ]
}

fn requests(shell, parent, entries) {
  case entries {
    [] -> []
    [#(i, start, event.Output(stop: event.Requested(request), ..)), ..entries] -> {
      let #(end, response, entries) = case entries {
        [
          #(_, end, event.Input(event.Continued(execute.Fetched(response)), ..)),
          ..entries
        ] -> #(end, response, entries)
        _ -> #(start, Error("no response was recorded"), entries)
      }
      let method = http.method_to_string(request.method) |> string.uppercase
      let attributes = [
        #("http.request.method", method),
        #("url.full", uri.to_string(request.to_uri(request))),
      ]
      let #(attributes, error) = case response {
        Ok(response) -> #(
          [
            #("http.response.status_code", int.to_string(response.status)),
            ..attributes
          ],
          None,
        )
        Error(reason) -> #(attributes, Some(reason))
      }
      let id = span_id(shell, i)
      [
        Span(id, Some(parent), method, True, start, end, attributes, error),
        ..requests(shell, parent, entries)
      ]
    }
    [_, ..entries] -> requests(shell, parent, entries)
  }
}

fn span_id(shell, i) {
  hex(<<shell:utf8, i:64>>, 8)
}

fn hex(seed, bytes) {
  let assert Ok(id) =
    crypto.hash(crypto.Sha256, seed) |> bit_array.slice(0, bytes)
  string.lowercase(bit_array.base16_encode(id))
}

/// An OTLP export request with every span of the shell.
pub fn encode(shell: String, spans: List(Span)) -> json.Json {
  let trace = hex(<<shell:utf8>>, 16)
  json.object([
    #(
      "resourceSpans",
      json.preprocessed_array([
        json.object([
          #(
            "resource",
            json.object([
              #("attributes", attributes([#("service.name", "eyg-cloud")])),
            ]),
          ),
          #(
            "scopeSpans",
            json.preprocessed_array([
              json.object([
                #(
                  "scope",
                  json.object([#("name", json.string("cloud/shells"))]),
                ),
                #("spans", json.array(spans, encode_span(trace, _))),
              ]),
            ]),
          ),
        ]),
      ]),
    ),
  ])
}

fn encode_span(trace, span: Span) {
  let kind = case span.client {
    True -> 3
    False -> 1
  }
  let status = case span.error {
    None -> [#("code", json.int(1))]
    Some(reason) -> [#("code", json.int(2)), #("message", json.string(reason))]
  }
  let parent = case span.parent {
    Some(parent) -> [#("parentSpanId", json.string(parent))]
    None -> []
  }
  json.object(
    [
      #("traceId", json.string(trace)),
      #("spanId", json.string(span.id)),
      ..parent
    ]
    |> list.append([
      #("name", json.string(span.name)),
      #("kind", json.int(kind)),
      #("startTimeUnixNano", json.string(int.to_string(span.start * 1000))),
      #("endTimeUnixNano", json.string(int.to_string(span.end * 1000))),
      #("attributes", attributes(span.attributes)),
      #("status", json.object(status)),
    ]),
  )
}

fn attributes(attributes) {
  json.array(attributes, fn(attribute: #(String, String)) {
    json.object([
      #("key", json.string(attribute.0)),
      #("value", json.object([#("stringValue", json.string(attribute.1))])),
    ])
  })
}
