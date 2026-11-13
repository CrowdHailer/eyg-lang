//// Langfuse authentication and trace links. Wire data uses the shared OTLP codec.

import glasshouse/session.{type Session}
import glasshouse/store.{type Sha256, type Store}
import glasshouse/telemetry
import gleam/bit_array
import gleam/http
import gleam/http/request.{type Request}
import gleam/json.{type Json}
import gleam/result
import gleam/string
import gleam/uri

pub type Span =
  telemetry.Span

pub fn trace_id(session: Session, sha256: Sha256) -> String {
  telemetry.trace_id(session, sha256)
}

pub fn spans(session: Session, store: Store, sha256: Sha256) -> List(Span) {
  telemetry.spans(session, store, sha256)
}

pub fn payload(session: Session, store: Store, sha256: Sha256) -> Json {
  telemetry.payload(session, store, sha256)
}

/// The request uploading spans to a Langfuse host such as `https://cloud.langfuse.com`.
pub fn request(
  host: String,
  public_key: String,
  secret_key: String,
  payload: Json,
) -> Result(Request(BitArray), String) {
  use parsed <- result.try(
    uri.parse(host) |> result.replace_error("invalid Langfuse host " <> host),
  )
  use base <- result.try(
    request.from_uri(parsed)
    |> result.replace_error("invalid Langfuse host " <> host),
  )
  // A host can be served under a path prefix.
  let prefix = case string.ends_with(parsed.path, "/") {
    True -> string.drop_end(parsed.path, 1)
    False -> parsed.path
  }
  let credentials =
    bit_array.base64_encode(
      <<public_key:utf8, ":":utf8, secret_key:utf8>>,
      True,
    )
  base
  |> request.set_method(http.Post)
  |> request.set_path(prefix <> "/api/public/otel/v1/traces")
  |> request.set_header("authorization", "Basic " <> credentials)
  |> request.set_header("content-type", "application/json")
  |> request.set_header("x-langfuse-ingestion-version", "4")
  |> request.set_body(<<json.to_string(payload):utf8>>)
  |> Ok
}

/// The address to view the trace in Langfuse.
pub fn trace_url(host: String, trace_id: String) -> String {
  let host = case string.ends_with(host, "/") {
    True -> string.drop_end(host, 1)
    False -> host
  }
  host <> "/trace/" <> trace_id
}
