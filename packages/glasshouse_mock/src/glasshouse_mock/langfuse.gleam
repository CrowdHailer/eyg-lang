//// A Langfuse mock, traces are received as OTLP JSON and can be read back.
////
//// Spans are mapped to traces and observations with the same attributes Langfuse reads,
//// `langfuse.observation.type`, `gen_ai.usage.*` and the `langfuse.*.metadata.*` prefixes.
//// Any `pk-lf-` and `sk-lf-` key pair is accepted.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import otel/clock
import otel/codec
import otel/span as otel_span

pub type Trace {
  Trace(
    id: String,
    name: String,
    session: String,
    started: Int,
    input: String,
    output: String,
    metadata: List(#(String, String)),
    observations: List(Observation),
  )
}

pub type Observation {
  Observation(
    id: String,
    parent: Option(String),
    type_: String,
    name: String,
    started: Int,
    ended: Int,
    model: String,
    input: String,
    output: String,
    input_tokens: Int,
    output_tokens: Int,
    metadata: List(#(String, String)),
    error: Option(String),
  )
}

pub type Store =
  Dict(String, Trace)

pub fn new() -> Store {
  dict.new()
}

/// Is the authorization header a Langfuse key pair.
pub fn authorized(header: Result(String, Nil)) -> Bool {
  case header {
    Ok("Basic " <> encoded) ->
      case bit_array.base64_decode(encoded) {
        Ok(decoded) ->
          case bit_array.to_string(decoded) {
            Ok(pair) ->
              case string.split_once(pair, ":") {
                Ok(#("pk-lf-" <> _, "sk-lf-" <> _)) -> True
                _ -> False
              }
            Error(Nil) -> False
          }
        Error(Nil) -> False
      }
    _ -> False
  }
}

type Span {
  Span(
    trace: String,
    id: String,
    parent: Option(String),
    name: String,
    started: Int,
    ended: Int,
    attributes: List(#(String, Attribute)),
    error: Option(String),
  )
}

type Attribute =
  otel_span.Attribute

fn milliseconds(time: clock.Time) {
  time.seconds * 1000 + time.nanoseconds / 1_000_000
}

/// Add the spans of an OTLP JSON export to the store.
pub fn ingest(store: Store, body: BitArray) -> Result(#(Store, Int), String) {
  use spans <- result.try(
    json.parse_bits(body, codec.spans())
    |> result.replace_error("not an OTLP JSON trace export"),
  )
  let spans =
    list.map(spans, fn(span) {
      Span(
        trace: span.trace_id,
        id: span.span_id,
        parent: span.parent_id,
        name: span.name,
        started: milliseconds(span.started),
        ended: milliseconds(span.ended),
        attributes: span.attributes,
        error: span.error,
      )
    })
  let store =
    list.fold(spans, store, fn(store, span) {
      let trace =
        dict.get(store, span.trace)
        |> result.unwrap(
          Trace(
            id: span.trace,
            name: "",
            session: "",
            started: span.started,
            input: "",
            output: "",
            metadata: [],
            observations: [],
          ),
        )
      let trace = case span.parent {
        None ->
          Trace(
            ..trace,
            name: text(span.attributes, "langfuse.trace.name")
              |> option.unwrap(span.name),
            session: text(span.attributes, "langfuse.session.id")
              |> option.unwrap(trace.session),
            started: span.started,
            input: text(span.attributes, "langfuse.trace.input")
              |> option.unwrap(trace.input),
            output: text(span.attributes, "langfuse.trace.output")
              |> option.unwrap(trace.output),
            metadata: metadata(span.attributes, "langfuse.trace.metadata."),
          )
        Some(_) -> trace
      }
      let observation =
        Observation(
          id: span.id,
          parent: span.parent,
          type_: text(span.attributes, "langfuse.observation.type")
            |> option.unwrap("span"),
          name: span.name,
          started: span.started,
          ended: span.ended,
          model: text(span.attributes, "gen_ai.request.model")
            |> option.unwrap(""),
          input: text(span.attributes, "langfuse.observation.input")
            |> option.unwrap(""),
          output: text(span.attributes, "langfuse.observation.output")
            |> option.unwrap(""),
          input_tokens: number(span.attributes, "gen_ai.usage.input_tokens"),
          output_tokens: number(span.attributes, "gen_ai.usage.output_tokens"),
          metadata: metadata(span.attributes, "langfuse.observation.metadata."),
          error: span.error,
        )
      let observations =
        trace.observations
        |> list.filter(fn(o) { o.id != observation.id })
        |> list.append([observation])
        |> list.sort(fn(a, b) { int.compare(a.started, b.started) })
      dict.insert(store, trace.id, Trace(..trace, observations:))
    })
  Ok(#(store, list.length(spans)))
}

fn text(attributes, key) {
  case list.key_find(attributes, key) {
    Ok(otel_span.Text(text)) -> Some(text)
    _ -> None
  }
}

fn number(attributes, key) {
  case list.key_find(attributes, key) {
    Ok(otel_span.Integer(n)) -> n
    _ -> 0
  }
}

fn metadata(attributes, prefix) {
  list.filter_map(attributes, fn(attribute) {
    let #(key, value) = attribute
    case string.starts_with(key, prefix) {
      True ->
        Ok(#(string.drop_start(key, string.length(prefix)), render(value)))
      False -> Error(Nil)
    }
  })
}

fn render(attribute) {
  case attribute {
    otel_span.Text(text) -> text
    otel_span.Integer(n) -> int.to_string(n)
    otel_span.Boolean(True) -> "true"
    otel_span.Boolean(False) -> "false"
    otel_span.Array(items) -> list.map(items, render) |> string.join("\n")
    otel_span.Real(value) -> float.to_string(value)
  }
}

/// Traces, newest first.
pub fn traces(store: Store) -> List(Trace) {
  dict.values(store)
  |> list.sort(fn(a, b) { int.compare(b.started, a.started) })
}

pub fn tokens(trace: Trace) -> Int {
  list.fold(trace.observations, 0, fn(total, o) {
    total + o.input_tokens + o.output_tokens
  })
}

pub fn trace_json(trace: Trace, observations: Bool) -> json.Json {
  let Trace(id:, name:, session:, started:, input:, output:, metadata:, ..) =
    trace
  json.object([
    #("id", json.string(id)),
    #("name", json.string(name)),
    #("sessionId", json.string(session)),
    #("timestamp", json.int(started)),
    #("input", json.string(input)),
    #("output", json.string(output)),
    #("metadata", pairs(metadata)),
    #("totalTokens", json.int(tokens(trace))),
    #("observations", case observations {
      True -> json.array(trace.observations, observation_json)
      False -> json.array(trace.observations, fn(o) { json.string(o.id) })
    }),
  ])
}

fn observation_json(observation: Observation) {
  json.object([
    #("id", json.string(observation.id)),
    #("parentObservationId", json.nullable(observation.parent, json.string)),
    #("type", json.string(string.uppercase(observation.type_))),
    #("name", json.string(observation.name)),
    #("startTime", json.int(observation.started)),
    #("endTime", json.int(observation.ended)),
    #("model", json.string(observation.model)),
    #("input", json.string(observation.input)),
    #("output", json.string(observation.output)),
    #(
      "usageDetails",
      json.object([
        #("input", json.int(observation.input_tokens)),
        #("output", json.int(observation.output_tokens)),
      ]),
    ),
    #("metadata", pairs(observation.metadata)),
    #(
      "level",
      json.string(case observation.error {
        Some(_) -> "ERROR"
        None -> "DEFAULT"
      }),
    ),
    #("statusMessage", json.nullable(observation.error, json.string)),
  ])
}

fn pairs(pairs: List(#(String, String))) {
  json.object(list.map(pairs, fn(pair) { #(pair.0, json.string(pair.1)) }))
}

/// The response for `GET /api/public/traces`.
pub fn list_json(store: Store) -> json.Json {
  let traces = traces(store)
  json.object([
    #("data", json.array(traces, trace_json(_, False))),
    #(
      "meta",
      json.object([
        #("page", json.int(1)),
        #("limit", json.int(list.length(traces))),
        #("totalItems", json.int(list.length(traces))),
        #("totalPages", json.int(1)),
      ]),
    ),
  ])
}
