//// OpenTelemetry spans for a session, made from its events.
////
//// The session is one span, each turn is a span in it and each request is a span in its turn.
//// A request span starts when the request is recorded and ends when its response is recorded.
//// Asking an llm for a completion is a span in the same way.
//// Spans are encoded as OTLP JSON, which can be posted to any OpenTelemetry collector.

import cloud/beam/execute
import cloud/sessions/event.{type Event}
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

/// `log` is every event of the session with the time it was recorded, in microseconds.
pub fn spans(session: String, log: List(#(Int, Event))) -> List(Span) {
  // Spans are numbered by their first event.
  let log = list.index_map(log, fn(entry, i) { #(i, entry.0, entry.1) })
  case log, list.last(log) {
    [#(_, start, _), ..], Ok(#(_, end, _)) -> {
      let id = span_id(session, -1)
      let attributes = [#("session.id", session)]
      let root = Span(id, None, "session", False, start, end, attributes, None)
      [root, ..list.flat_map(turns(log), turn_spans(session, id, _))]
    }
    _, _ -> []
  }
}

fn turns(log) {
  case log {
    [] -> []
    [#(i, at, event.Started(code, policy)), ..log] ->
      turn(i, at, #("eyg.code", code), policy, log)
    [#(i, at, event.Sent(message, policy)), ..log] ->
      turn(i, at, #("eyg.message", message), policy, log)
    [_, ..log] -> turns(log)
  }
}

fn turn(i, at, input, policy, log: List(#(Int, Int, Event))) {
  let #(events, log) =
    list.split_while(log, fn(entry) {
      case entry.2 {
        event.Started(..) | event.Sent(..) -> False
        _ -> True
      }
    })
  [#(i, at, input, policy, events), ..turns(log)]
}

fn turn_spans(session, parent, turn) {
  let #(i, start, input, policy, events) = turn
  let id = span_id(session, i)
  let finished =
    list.find_map(events, fn(entry) {
      case entry {
        #(_, at, event.Finished(outcome, _, _)) -> Ok(#(at, outcome))
        _ -> Error(Nil)
      }
    })
  let #(end, error) = case finished, list.last(events) {
    Ok(#(at, Ok(_))), _ -> #(at, None)
    Ok(#(at, Error(reason))), _ -> #(at, Some(reason))
    Error(Nil), Ok(#(_, at, _)) -> #(at, Some("unfinished"))
    Error(Nil), Error(Nil) -> #(start, Some("unfinished"))
  }
  let attributes = [input, #("eyg.policy", v1.to_string(policy))]
  [
    Span(id, Some(parent), "turn", False, start, end, attributes, error),
    ..requests(session, id, events)
  ]
}

fn requests(session, parent, events) {
  case events {
    [] -> []
    [#(i, start, event.Requested(request, _)), ..events] -> {
      let #(end, response, events) = case events {
        [#(_, end, event.Answered(execute.Fetched(response))), ..events] -> #(
          end,
          response,
          events,
        )
        _ -> #(start, Error("no response was recorded"), events)
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
      let id = span_id(session, i)
      [
        Span(id, Some(parent), method, True, start, end, attributes, error),
        ..requests(session, parent, events)
      ]
    }
    [#(i, start, event.Asked(..)), ..events] -> {
      let #(end, error, events) = case events {
        [#(_, end, event.Answered(execute.Completed(Ok(_)))), ..events] -> #(
          end,
          None,
          events,
        )
        [#(_, end, event.Answered(execute.Completed(Error(reason)))), ..events] -> #(
          end,
          Some(reason),
          events,
        )
        _ -> #(start, Some("no completion was recorded"), events)
      }
      let attributes = [#("gen_ai.operation.name", "chat")]
      let id = span_id(session, i)
      [
        Span(id, Some(parent), "chat", True, start, end, attributes, error),
        ..requests(session, parent, events)
      ]
    }
    [_, ..events] -> requests(session, parent, events)
  }
}

fn span_id(session, i) {
  hex(<<session:utf8, i:64>>, 8)
}

fn hex(seed, bytes) {
  let assert Ok(id) =
    crypto.hash(crypto.Sha256, seed) |> bit_array.slice(0, bytes)
  string.lowercase(bit_array.base16_encode(id))
}

/// An OTLP export request with every span of the session.
pub fn encode(session: String, spans: List(Span)) -> json.Json {
  let trace = hex(<<session:utf8>>, 16)
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
                  json.object([#("name", json.string("cloud/sessions"))]),
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
