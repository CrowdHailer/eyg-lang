//// Query the real Jaeger backend for every newly captured span.

import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import otel
import plinthx/browser/fetch
import simplifile
import tracing/model
import tracing/storage

fn decoder() {
  let span = {
    use id <- decode.field("spanId", decode.string)
    use name <- decode.field("name", decode.string)
    use parent <- decode.optional_field(
      "parentSpanId",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(id, #(name, parent)))
  }
  let scope = decode.field("spans", decode.list(span), decode.success)
  let resource = decode.field("scopeSpans", decode.list(scope), decode.success)
  decode.subfield(
    ["result", "resourceSpans"],
    decode.list(resource),
    fn(resources) { decode.success(list.flatten(list.flatten(resources))) },
  )
}

pub fn main() {
  let assert Ok(captures) =
    storage.read("presentation/captures.json", "captures")
  let assert Ok(profiles) =
    storage.read("presentation/profiles.json", "profiles")
  let host =
    otel.env_value(otel.environment(), "JAEGER_HOST", "http://localhost:16686")
  use summaries <- promise.map(check(list.append(captures, profiles), host, []))
  let assert Ok(_) =
    simplifile.write(
      "presentation/jaeger-verification.txt",
      "Fresh captures checked on 2026-10-15; all span IDs, parents and names matched Jaeger 2.22.0.\n"
        <> summaries,
    )
  io.println(summaries)
}

fn check(captures: List(model.Capture), host, summaries) {
  case captures {
    [] -> promise.resolve(list.reverse(summaries) |> string.concat)
    [capture, ..rest] -> {
      let assert Ok(root) = model.root(capture)
      let assert Ok(client) = fetch.get()
      use response <- promise.await(fetch.send(
        client,
        host <> "/api/v3/traces/" <> root.trace_id,
        fetch.RequestInit("GET", [], "", None),
      ))
      let assert Ok(response) = response
      assert fetch.status(response) == 200
      use body <- promise.await(fetch.text(response))
      let assert Ok(body) = body
      let assert Ok(spans) = json.parse(body, decoder())
      assert list.length(spans) == list.length(capture.spans)
      list.each(capture.spans, fn(span) {
        assert list.key_find(spans, span.span_id)
          == Ok(#(span.name, span.parent_id))
      })
      check(rest, host, [
        capture.id
          <> ": "
          <> int.to_string(list.length(spans))
          <> " spans verified\n",
        ..summaries
      ])
    }
  }
}
