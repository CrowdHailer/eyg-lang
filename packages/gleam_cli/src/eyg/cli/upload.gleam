//// Upload the observability half of a trace to Langfuse.
////
//// Credentials are read from `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY`,
//// `LANGFUSE_HOST` defaults to Langfuse Cloud.
//// The archive is updated with a link to the uploaded trace.

import eyg/cli/internal/config
import eyg/cli/internal/traces
import glasshouse/archive.{type Archive}
import glasshouse/langfuse
import glasshouse/telemetry
import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import loam/system
import otel

pub const default_host = "https://cloud.langfuse.com"

pub type Langfuse {
  Langfuse(host: String, public_key: String, secret_key: String)
}

/// Langfuse credentials, if both keys are set.
pub fn configured() -> system.Effect(Option(Langfuse)) {
  use host <- system.then(system.env("LANGFUSE_HOST"))
  use public_key <- system.then(system.env("LANGFUSE_PUBLIC_KEY"))
  use secret_key <- system.map(system.env("LANGFUSE_SECRET_KEY"))
  case public_key, secret_key {
    Some(public_key), Some(secret_key) ->
      Some(Langfuse(
        host: option.unwrap(host, default_host),
        public_key:,
        secret_key:,
      ))
    _, _ -> None
  }
}

/// Send the spans of a session, returning the archive with a link to the trace.
pub fn upload(
  archive: Archive,
  credentials: Langfuse,
) -> system.Effect(Result(Archive, String)) {
  let Langfuse(host:, public_key:, secret_key:) = credentials
  let payload = langfuse.payload(archive.session, archive.store, traces.sha256)
  use request <- system.try(langfuse.request(
    host,
    public_key,
    secret_key,
    payload,
  ))
  use response <- system.map(system.fetch(request))
  case response {
    Ok(response) if response.status >= 200 && response.status < 300 -> {
      use text <- result.try(
        bit_array.to_string(response.body)
        |> result.replace_error("invalid OTLP response encoding"),
      )
      use Nil <- result.try(otel.acceptance(text))
      let trace_id = langfuse.trace_id(archive.session, traces.sha256)
      Ok(archive.add_link(archive, archive.Langfuse(host:, trace_id:)))
    }
    Ok(response) ->
      Error(
        "Langfuse responded with status "
        <> int.to_string(response.status)
        <> ": "
        <> result.unwrap(bit_array.to_string(response.body), ""),
      )
    Error(_) -> Error("failed to reach Langfuse at " <> host)
  }
}

/// `eyg upload <trace>`
pub fn execute(
  path: String,
  _config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use credentials <- system.then(configured())
  case credentials {
    None -> upload_to_collector(path)
    Some(credentials) -> {
      use archive <- system.then(traces.load(path))
      use archive <- system.try(archive)
      use uploaded <- system.then(upload(archive, credentials))
      use archive <- system.try(uploaded)
      use written <- system.then(system.write_file(
        path,
        archive.to_string(archive),
      ))
      use Nil <- system.try(written)
      let trace_id = langfuse.trace_id(archive.session, traces.sha256)
      use Nil <- system.then(system.stdout(
        "uploaded " <> langfuse.trace_url(credentials.host, trace_id),
      ))
      system.Done(Ok(0))
    }
  }
}

fn upload_to_collector(path) {
  use env <- system.then(
    system.traverse(
      [
        "OTEL_EXPORTER_OTLP_ENDPOINT", "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
        "OTEL_EXPORTER_OTLP_HEADERS", "OTEL_EXPORTER_OTLP_TRACES_HEADERS",
        "OTEL_SERVICE_NAME", "OTEL_SDK_DISABLED",
      ],
      fn(name) {
        use value <- system.map(system.env(name))
        #(name, option.unwrap(value, ""))
      },
    ),
  )
  let exporter = otel.configure(env, "eyg", "glasshouse", [])
  case exporter.endpoint {
    None ->
      system.Done(Error(
        "set OTEL_EXPORTER_OTLP_ENDPOINT or LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY to upload",
      ))
    Some(endpoint) -> {
      use archived <- system.then(traces.load(path))
      use archived <- system.try(archived)
      use sent <- system.then(send_batches(
        telemetry.otel_spans(archived.session, archived.store, traces.sha256),
        exporter,
        endpoint,
      ))
      use Nil <- system.try(sent)
      use Nil <- system.map(system.stdout(
        "uploaded trace " <> telemetry.trace_id(archived.session, traces.sha256),
      ))
      Ok(0)
    }
  }
}

fn send_batches(spans, exporter: otel.Exporter, endpoint) {
  case spans {
    [] -> system.Done(Ok(Nil))
    _ -> {
      let #(batch, rest) = list.split(spans, otel.batch_size)
      use request <- system.try(
        request.to(endpoint) |> result.replace_error("invalid OTLP endpoint"),
      )
      let request =
        request
        |> request.set_method(http.Post)
        |> request.set_header("content-type", "application/json")
        |> request.set_body(<<
          { json.to_string(otel.encode(exporter, batch)) }:utf8,
        >>)
      let request =
        list.fold(exporter.headers, request, fn(request, pair) {
          request.set_header(request, pair.0, pair.1)
        })
      use response <- system.then(system.fetch(request))
      use response <- system.try(result.replace_error(
        response,
        "failed to reach OTLP collector",
      ))
      use Nil <- system.try(
        case response.status >= 200 && response.status < 300 {
          True ->
            bit_array.to_string(response.body)
            |> result.replace_error("invalid OTLP response encoding")
            |> result.try(otel.acceptance)
          False ->
            Error(
              "OTLP collector returned HTTP " <> int.to_string(response.status),
            )
        },
      )
      send_batches(rest, exporter, endpoint)
    }
  }
}
