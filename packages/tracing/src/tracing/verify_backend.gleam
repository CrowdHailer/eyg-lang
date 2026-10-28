//// Upload an archive and check every span's identity and parent in a real backend.

import glasshouse/archive
import glasshouse/langfuse
import glasshouse/sha256
import glasshouse/telemetry
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http/request
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import gleam/uri
import otel
import otel/span as attribute
import plinthx/browser/fetch
import plinthx/node/timers
import simplifile

pub fn main() {
  let env = otel.environment()
  let path = otel.env_value(env, "TRACE_ARCHIVE", "recordings/trajectory.json")
  let assert Ok(text) = simplifile.read(path)
  let assert Ok(archived) = archive.from_string(text)
  let expected = telemetry.spans(archived.session, archived.store, sha256.hash)
  let trace_id = telemetry.trace_id(archived.session, sha256.hash)
  let backend = otel.env_value(env, "TRACE_BACKEND", "jaeger")
  let host = case backend {
    "langfuse" -> otel.env_value(env, "LANGFUSE_HOST", "http://localhost:3000")
    "jaeger" -> otel.env_value(env, "JAEGER_HOST", "http://localhost:16686")
    _ -> panic as "TRACE_BACKEND must be jaeger or langfuse"
  }
  let authorization = case backend {
    "langfuse" -> [
      #(
        "authorization",
        "Basic "
          <> bit_array.base64_encode(
          <<
            { otel.env_value(env, "LANGFUSE_PUBLIC_KEY", "pk-lf-eyg-local") }:utf8,
            ":":utf8,
            { otel.env_value(env, "LANGFUSE_SECRET_KEY", "sk-lf-eyg-local") }:utf8,
          >>,
          True,
        ),
      ),
    ]
    _ -> []
  }
  let payload = telemetry.payload(archived.session, archived.store, sha256.hash)
  let upload = case otel.env_value(env, "VERIFY_ONLY", "false") {
    "true" -> promise.resolve(Ok(Nil))
    _ ->
      case backend {
        "langfuse" -> {
          let assert Ok(request) =
            langfuse.request(
              host,
              otel.env_value(env, "LANGFUSE_PUBLIC_KEY", "pk-lf-eyg-local"),
              otel.env_value(env, "LANGFUSE_SECRET_KEY", "sk-lf-eyg-local"),
              payload,
            )
          otel.post_with_headers(
            uri.to_string(request.to_uri(request)),
            json.to_string(payload),
            request.headers,
          )
        }
        _ ->
          otel.post("http://localhost:4318/v1/traces", json.to_string(payload))
      }
  }
  use uploaded <- promise.await(upload)
  let assert Ok(_) = uploaded
  io.println("Upload accepted; waiting for " <> backend <> " indexing.")
  let path = case backend {
    "langfuse" ->
      "/api/public/v2/observations?limit=100&fields=core,basic,usage,model&traceId="
      <> trace_id
    _ -> "/api/v3/traces/" <> trace_id
  }
  use observed <- promise.map(read(
    host <> path,
    authorization,
    backend,
    list.length(expected),
    30,
  ))
  let assert Ok(#(observed, text)) = observed
  assert list.length(observed) == list.length(expected)
  list.each(expected, fn(span) {
    let assert Ok(found) = list.key_find(observed, span.id)
    assert found.0 == span.parent
    assert found.1 == span.name
  })
  case backend {
    "langfuse" -> verify_langfuse(text, expected)
    _ -> Nil
  }
  let assert Ok(_) =
    simplifile.write(
      "recordings/" <> backend <> "-verification.txt",
      "trace "
        <> trace_id
        <> "\n"
        <> int.to_string(list.length(expected))
        <> " spans; all IDs, parents and names verified\n"
        <> case backend {
        "langfuse" ->
          "Observation types, session grouping, models and token counts verified\n"
        _ -> ""
      },
    )
  io.println(
    backend <> ": " <> int.to_string(list.length(expected)) <> " spans verified",
  )
}

fn read(url, headers, backend, count, remaining) {
  let assert Ok(client) = fetch.get()
  use response <- promise.await(fetch.send(
    client,
    url,
    fetch.RequestInit("GET", headers, "", None),
  ))
  let body = case response {
    Ok(response) ->
      case fetch.status(response) {
        200 -> fetch.text(response)
        _ -> promise.resolve(Error("backend has not indexed the trace"))
      }
    _ -> promise.resolve(Error("backend has not indexed the trace"))
  }
  use body <- promise.await(body)
  let parsed =
    result.try(body, fn(text) {
      json.parse(text, decoder(backend))
      |> result.replace_error("invalid backend response")
      |> result.map(fn(spans) { #(spans, text) })
    })
  let complete = case parsed {
    Ok(#(spans, _)) -> list.length(spans) == count
    _ -> False
  }
  case complete, remaining {
    True, _ | _, 0 -> promise.resolve(parsed)
    False, _ -> {
      use _ <- promise.await(timers.sleep(1000))
      read(url, headers, backend, count, remaining - 1)
    }
  }
}

fn verify_langfuse(text, expected: List(telemetry.Span)) {
  let observation = {
    use id <- decode.field("id", decode.string)
    use type_ <- decode.field("type", decode.string)
    use model <- decode.optional_field("model", "", decode.string)
    use input <- decode.optional_field("inputUsage", 0, decode.int)
    use output <- decode.optional_field("outputUsage", 0, decode.int)
    use session <- decode.optional_field("sessionId", "", decode.string)
    decode.success(#(id, #(type_, model, input, output, session)))
  }
  let assert Ok(observations) =
    json.parse(
      text,
      decode.field("data", decode.list(observation), decode.success),
    )
  list.each(expected, fn(span) {
    let assert Ok(found) = list.key_find(observations, span.id)
    assert found.0
      == string.uppercase(text_attribute(span, "langfuse.observation.type"))
    assert found.1 == text_attribute(span, "gen_ai.request.model")
    assert found.2 == integer_attribute(span, "gen_ai.usage.input_tokens")
    assert found.3 == integer_attribute(span, "gen_ai.usage.output_tokens")
    assert found.4 == text_attribute(span, "langfuse.session.id")
  })
}

fn text_attribute(span: telemetry.Span, key) {
  case list.key_find(span.attributes, key) {
    Ok(attribute.Text(value)) -> value
    _ -> ""
  }
}

fn integer_attribute(span: telemetry.Span, key) {
  case list.key_find(span.attributes, key) {
    Ok(attribute.Integer(value)) -> value
    _ -> 0
  }
}

fn decoder(backend) {
  let span = {
    use id <- decode.field(
      case backend {
        "langfuse" -> "id"
        _ -> "spanId"
      },
      decode.string,
    )
    use parent <- decode.optional_field(
      case backend {
        "langfuse" -> "parentObservationId"
        _ -> "parentSpanId"
      },
      None,
      decode.optional(decode.string),
    )
    use name <- decode.field("name", decode.string)
    decode.success(#(id, #(parent, name)))
  }
  case backend {
    "langfuse" -> decode.field("data", decode.list(span), decode.success)
    _ -> {
      let scope = decode.field("spans", decode.list(span), decode.success)
      let resource =
        decode.field("scopeSpans", decode.list(scope), decode.success)
      decode.subfield(
        ["result", "resourceSpans"],
        decode.list(resource),
        fn(resources) { decode.success(list.flatten(list.flatten(resources))) },
      )
    }
  }
}
