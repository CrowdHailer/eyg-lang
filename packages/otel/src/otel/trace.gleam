//// Portable OTLP resource/scope encoding, without host environment or transport.

import gleam/json
import otel/span

pub fn encode(
  service: String,
  scope_name: String,
  attributes: List(#(String, span.Attribute)),
  spans: List(span.Span),
) -> json.Json {
  let resource =
    json.object([
      #(
        "attributes",
        json.array(
          [#("service.name", span.Text(service)), ..attributes],
          span.attribute_json,
        ),
      ),
    ])
  let scope =
    json.object([
      #("scope", json.object([#("name", json.string(scope_name))])),
      #("spans", json.array(spans, span.encode)),
    ])
  json.object([
    #(
      "resourceSpans",
      json.array(
        [
          json.object([
            #("resource", resource),
            #("scopeSpans", json.array([scope], fn(value) { value })),
          ]),
        ],
        fn(value) { value },
      ),
    ),
  ])
}
