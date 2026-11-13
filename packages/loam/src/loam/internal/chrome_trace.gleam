//// Pure conversion shared by the host and offline tools.

import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import otel/clock
import otel/span as otel

pub fn attribute(span: otel.Span, key: String, default: String) -> String {
  case list.key_find(span.attributes, key) {
    Ok(otel.Text(value)) -> value
    Ok(otel.Integer(value)) -> int.to_string(value)
    Ok(value) -> json.to_string(otel.value_json(value))
    Error(_) -> default
  }
}

pub fn compare(a: otel.Span, b: otel.Span) -> order.Order {
  int.compare(clock.difference(a.started, b.started), 0)
}

pub fn encode(recorded: List(otel.Span), service: String) -> json.Json {
  let spans = list.sort(recorded, compare)
  let origin = case spans {
    [] -> clock.Time(0, 0)
    [span, ..] -> span.started
  }
  let metadata = fn(name, tid) {
    json.object([
      #("name", json.string(name)),
      #("ph", json.string("M")),
      #("pid", json.int(1)),
      #("tid", json.int(tid)),
      #("args", json.object([#("name", json.string("EYG evaluation"))])),
    ])
  }
  let events = list.map(spans, fn(span) { event(span, origin) })
  json.object([
    #(
      "traceEvents",
      json.array(
        [metadata("process_name", 0), metadata("thread_name", 1), ..events],
        fn(value) { value },
      ),
    ),
    #("displayTimeUnit", json.string("ms")),
    #(
      "otherData",
      json.object([
        #("service", json.string(service)),
        #(
          "measurement",
          json.string(
            "Instrumented EYG wall time, including effect suspension; not sampled CPU time. Self time excludes children. Active time excludes host-effect subtrees, not GC or profiler overhead.",
          ),
        ),
      ]),
    ),
  ])
}

fn event(span: otel.Span, origin: clock.Time) -> json.Json {
  let attributes =
    list.map(span.attributes, fn(pair) {
      #(
        pair.0,
        json.string(case pair.1 {
          otel.Text(value) -> value
          otel.Integer(value) -> int.to_string(value)
          value -> json.to_string(otel.value_json(value))
        }),
      )
    })
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
    #("name", json.string(span.name)),
    #(
      "cat",
      json.string(case attribute(span, "eyg.profile.kind", "") {
        "effect" -> "eyg.effects"
        _ -> "eyg.functions"
      }),
    ),
    #("ph", json.string("X")),
    #("pid", json.int(1)),
    #("tid", json.int(1)),
    #(
      "ts",
      json.float(int.to_float(clock.difference(span.started, origin)) /. 1000.0),
    ),
    #(
      "dur",
      json.float(
        int.to_float(clock.difference(span.ended, span.started)) /. 1000.0,
      ),
    ),
    #(
      "args",
      json.object([
        #(
          "data",
          json.object([
            #("functionName", json.string(span.name)),
            #("scriptId", json.string("eyg")),
            #(
              "url",
              json.string(attribute(span, "code.file.path", "eyg://evaluation")),
            ),
            #(
              "lineNumber",
              json.int(int.max(
                0,
                {
                  attribute(span, "code.line.number", "1")
                  |> int.parse
                  |> result.unwrap(1)
                }
                  - 1,
              )),
            ),
            #("columnNumber", json.int(0)),
          ]),
        ),
        #(
          "eyg",
          json.object(
            list.append(attributes, [
              #("traceId", json.string(span.trace_id)),
              #("spanId", json.string(span.span_id)),
              #("status", status),
              ..parent
            ]),
          ),
        ),
      ]),
    ),
  ])
}
