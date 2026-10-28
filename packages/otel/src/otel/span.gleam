//// Portable span data and OTLP encoding. No host environment or transport.

import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import otel/clock.{type Time}

pub type Attribute {
  Text(String)
  Integer(Int)
  Boolean(Bool)
  Real(Float)
  Array(List(Attribute))
}

pub type Span {
  Span(
    trace_id: String,
    span_id: String,
    parent_id: Option(String),
    name: String,
    started: Time,
    ended: Time,
    attributes: List(#(String, Attribute)),
    error: Option(String),
  )
}

pub fn text_attributes(attributes: List(#(String, String))) {
  list.map(attributes, fn(pair) { #(pair.0, Text(pair.1)) })
}

pub fn attribute_json(pair: #(String, Attribute)) -> json.Json {
  json.object([#("key", json.string(pair.0)), #("value", value_json(pair.1))])
}

pub fn value_json(attribute: Attribute) -> json.Json {
  case attribute {
    Text(value) -> json.object([#("stringValue", json.string(value))])
    Integer(value) ->
      json.object([#("intValue", json.string(int.to_string(value)))])
    Boolean(value) -> json.object([#("boolValue", json.bool(value))])
    Real(value) -> json.object([#("doubleValue", json.float(value))])
    Array(values) ->
      json.object([
        #(
          "arrayValue",
          json.object([
            #("values", json.array(values, value_json)),
          ]),
        ),
      ])
  }
}

pub fn encode(span: Span) -> json.Json {
  let parent = case span.parent_id {
    None -> []
    Some(id) -> [#("parentSpanId", json.string(id))]
  }
  let status = case span.error {
    None -> json.object([#("code", json.int(1))])
    Some(message) ->
      json.object([#("code", json.int(2)), #("message", json.string(message))])
  }
  json.object([
    #("traceId", json.string(span.trace_id)),
    #("spanId", json.string(span.span_id)),
    #("name", json.string(span.name)),
    #("kind", json.int(1)),
    #("startTimeUnixNano", json.string(clock.encode(span.started))),
    #("endTimeUnixNano", json.string(clock.encode(span.ended))),
    #("status", status),
    #("attributes", json.array(span.attributes, attribute_json)),
    ..parent
  ])
}
