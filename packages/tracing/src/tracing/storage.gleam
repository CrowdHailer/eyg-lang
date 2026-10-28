import gleam/json
import gleam/result
import otel
import simplifile
import tracing/model

pub fn read(
  path: String,
  field: String,
) -> Result(List(model.Capture), String) {
  use text <- result.try(
    simplifile.read(path) |> result.map_error(simplifile.describe_error),
  )
  json.parse(text, model.collection(field))
  |> result.replace_error("invalid trace collection: " <> path)
}

pub fn payload(capture: model.Capture) -> json.Json {
  let profile = case model.root(capture) {
    Ok(root) -> root.name == "eyg.profile"
    Error(_) -> False
  }
  otel.encode(
    otel.configure([], "eyg-" <> capture.id, "eyg.loam", [
      #("eyg.trace.mode", case profile {
        True -> "profile"
        False -> "effects"
      }),
    ]),
    capture.spans,
  )
}

pub fn encode(capture: model.Capture) -> json.Json {
  let trace_id = case model.root(capture) {
    Ok(root) -> root.trace_id
    Error(_) -> ""
  }
  json.object([
    #("id", json.string(capture.id)),
    #("title", json.string(capture.title)),
    #("exit", json.int(capture.exit)),
    #("stdout", json.string(capture.stdout)),
    #("stderr", json.string(capture.stderr)),
    #("source", json.string(capture.source)),
    #("otlp", payload(capture)),
    #("delay", json.int(capture.delay)),
    #("traceId", json.string(trace_id)),
    #(
      "requests",
      json.array(capture.requests, fn(pair) {
        json.object([
          #("path", json.string(pair.0)),
          #("status", json.int(pair.1)),
        ])
      }),
    ),
  ])
}

pub fn collection(field: String, captures: List(model.Capture)) -> json.Json {
  json.object([#(field, json.array(captures, encode))])
}

pub fn write(path: String, content: String) -> Result(Nil, String) {
  simplifile.write(path, content) |> result.map_error(simplifile.describe_error)
}

pub fn write_json(path: String, content: json.Json) -> Result(Nil, String) {
  write(path, json.to_string(content) <> "\n")
}
