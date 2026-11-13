//// Minimal immutable OTLP trace data and HTTP JSON export.

import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import otel/clock
import otel/span
import otel/trace
import plinthx/browser/abort_signal
import plinthx/browser/fetch
import plinthx/node/process

pub const batch_size = 128

pub type Attribute =
  span.Attribute

pub type Span =
  span.Span

pub type Exporter {
  Exporter(
    endpoint: Option(String),
    disabled: Bool,
    service: String,
    scope: String,
    attributes: List(#(String, Attribute)),
    headers: List(#(String, String)),
    warned: Bool,
  )
}

pub fn environment() -> List(#(String, String)) {
  case process.get() {
    Ok(p) -> process.env(p)
    Error(_) -> []
  }
}

pub fn configure(env, service, scope, attributes) -> Exporter {
  let disabled =
    string.lowercase(env_value(env, "OTEL_SDK_DISABLED", "false")) == "true"
  let base = env_value(env, "OTEL_EXPORTER_OTLP_ENDPOINT", "")
  let endpoint =
    env_value(env, "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", case base {
      "" -> ""
      _ -> trim_slashes(base) <> "/v1/traces"
    })
  Exporter(
    case disabled, endpoint {
      True, _ | _, "" -> None
      _, url -> Some(url)
    },
    disabled,
    env_value(env, "OTEL_SERVICE_NAME", service),
    scope,
    span.text_attributes(attributes),
    headers(env_value(
      env,
      "OTEL_EXPORTER_OTLP_TRACES_HEADERS",
      env_value(env, "OTEL_EXPORTER_OTLP_HEADERS", ""),
    )),
    False,
  )
}

fn headers(value: String) -> List(#(String, String)) {
  value
  |> string.split(",")
  |> list.filter_map(fn(pair) {
    use #(name, value) <- result.try(string.split_once(pair, "="))
    use value <- result.try(uri.percent_decode(string.trim(value)))
    Ok(#(string.trim(name), value))
  })
}

pub fn env_value(env, name, default) {
  case list.key_find(env, name) {
    Ok("") | Error(_) -> default
    Ok(value) -> value
  }
}

fn trim_slashes(value) {
  case string.ends_with(value, "/") {
    True -> trim_slashes(string.drop_end(value, 1))
    False -> value
  }
}

pub fn exporter(service, scope, attributes) {
  configure(environment(), service, scope, attributes)
}

pub fn enabled(exporter: Exporter) -> Bool {
  option.is_some(exporter.endpoint)
}

fn random_id(bytes: Int) -> String {
  crypto.strong_random_bytes(bytes)
  |> bit_array.base16_encode
  |> string.lowercase
}

pub fn trace_id() -> String {
  random_id(16)
}

pub fn start_span(trace_id, parent_id, name, attributes) -> Span {
  let time = clock.now()
  span.Span(
    trace_id,
    random_id(8),
    parent_id,
    name,
    time,
    time,
    span.text_attributes(attributes),
    None,
  )
}

pub fn end_span(value: Span, error: Option(String)) -> Span {
  span.Span(..value, ended: clock.now(), error:)
}

pub fn encode(exporter: Exporter, spans: List(Span)) -> json.Json {
  trace.encode(exporter.service, exporter.scope, exporter.attributes, spans)
}

pub fn warn(exporter: Exporter, message: String) -> Exporter {
  case exporter.warned {
    True -> exporter
    False -> {
      io.print_error("otel: " <> message <> "\n")
      Exporter(..exporter, warned: True)
    }
  }
}

/// Return updated diagnostic state so failures are reported at most once per run.
pub fn export_spans(
  exporter: Exporter,
  spans: List(Span),
) -> Promise(Exporter) {
  case exporter.endpoint, spans {
    None, _ | _, [] -> promise.resolve(exporter)
    Some(endpoint), _ -> {
      let #(batch, rest) = list.split(spans, batch_size)
      use response <- promise.await(post_with_headers(
        endpoint,
        encode(exporter, batch) |> json.to_string,
        exporter.headers,
      ))
      let exporter = case response {
        Ok(_) -> exporter
        Error(message) -> warn(exporter, message)
      }
      export_spans(exporter, rest)
    }
  }
}

/// Send one OTLP JSON request, retaining the timeout until its body is consumed.
pub fn post(endpoint: String, body: String) -> Promise(Result(Nil, String)) {
  post_with_headers(endpoint, body, [])
}

pub fn post_with_headers(
  endpoint: String,
  body: String,
  headers: List(#(String, String)),
) -> Promise(Result(Nil, String)) {
  let setup = {
    use fetch <- result.try(
      fetch.get() |> result.replace_error("fetch unavailable"),
    )
    use constructor <- result.try(
      abort_signal.get() |> result.replace_error("AbortSignal unavailable"),
    )
    use signal <- result.try(abort_signal.timeout(constructor, 2000))
    Ok(#(fetch, signal))
  }
  case setup {
    Error(message) -> promise.resolve(Error("export failed: " <> message))
    Ok(#(client, signal)) -> {
      use response <- promise.await(fetch.send(
        client,
        endpoint,
        fetch.RequestInit(
          "POST",
          [#("content-type", "application/json"), ..headers],
          body,
          Some(signal),
        ),
      ))
      case response {
        Error(message) -> promise.resolve(Error("export failed: " <> message))
        Ok(response) -> {
          use body <- promise.map(fetch.text(response))
          case
            fetch.status(response) >= 200 && fetch.status(response) < 300,
            body
          {
            False, _ ->
              Error(
                "export failed: collector returned HTTP "
                <> int.to_string(fetch.status(response)),
              )
            True, Error(message) -> Error("export failed: " <> message)
            True, Ok(body) -> acceptance(body)
          }
        }
      }
    }
  }
}

pub fn acceptance(body: String) -> Result(Nil, String) {
  case body {
    "" -> Ok(Nil)
    _ -> {
      let partial = {
        use rejected <- decode.optional_field(
          "rejectedSpans",
          "0",
          decode.one_of(decode.string, [decode.map(decode.int, int.to_string)]),
        )
        use message <- decode.optional_field("errorMessage", "", decode.string)
        decode.success(#(rejected, message))
      }
      let decoder = {
        use partial <- decode.optional_field(
          "partialSuccess",
          #("0", ""),
          partial,
        )
        decode.success(partial)
      }
      case json.parse(body, decoder) {
        Ok(#("0", "")) -> Ok(Nil)
        Ok(#(rejected, message)) ->
          Error(
            "collector partially accepted traces: "
            <> case message {
              "" -> rejected
              _ -> message
            },
          )
        Error(_) -> Error("export failed: invalid OTLP response")
      }
    }
  }
}
