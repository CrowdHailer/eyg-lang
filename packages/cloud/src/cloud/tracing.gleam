//// Tracing of EYG programs, as OpenTelemetry spans.
////
//// Tracing is at the language level: every program run is an `eyg.run` span
//// and every effect it performs is an `eyg.effect.<Name>` span inside it,
//// with the policy's decision and whether the effect failed.
//// Function calls are not traced. The cloud adds spans for what starts programs:
//// agent turns, model completions, triggers, invocations, web shell cells and API calls.
////
//// Spans are recorded by one tracer per cloud. It keeps the most recent spans,
//// read with the `Traces` operation of the configuration API, and exports them to an
//// OTLP/HTTP JSON collector when `OTEL_EXPORTER_OTLP_ENDPOINT` or
//// `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` is set, see `guides/cloud/tracing.md`.
//// Without a tracer, as in tests, spans are dropped.

import envoy
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/uri
import otel/clock
import otel/span
import otel/trace

pub type Attribute =
  span.Attribute

/// Where new spans belong, the trace and the span that is their parent.
pub type Context {
  Context(trace_id: String, span_id: String)
}

/// A span that has started and not yet ended.
pub opaque type Open {
  Open(span: span.Span)
}

pub type Message {
  Record(span.Span)
  Flush
  Recent(limit: Int, reply: Subject(List(span.Span)))
}

/// The most spans kept for reading, and sent in one request.
const keep = 2000

const batch = 128

/// Start a span, a child of `parent` or the root of a new trace.
pub fn start(
  name: String,
  parent: Option(Context),
  attributes: List(#(String, Attribute)),
) -> Open {
  let #(trace_id, parent_id) = case parent {
    Some(Context(trace_id:, span_id:)) -> #(trace_id, Some(span_id))
    None -> #(id(16), None)
  }
  let now = clock.now()
  Open(span.Span(
    trace_id:,
    span_id: id(8),
    parent_id:,
    name:,
    started: now,
    ended: now,
    attributes:,
    error: None,
  ))
}

/// The context for spans inside an open span.
pub fn context(open: Open) -> Context {
  Context(open.span.trace_id, open.span.span_id)
}

/// End a span, recording it with any extra attributes and an error if it failed.
pub fn end(
  open: Open,
  attributes: List(#(String, Attribute)),
  error: Option(String),
) -> Nil {
  let span =
    span.Span(
      ..open.span,
      ended: clock.now(),
      attributes: list.append(open.span.attributes, attributes),
      error:,
    )
  case tracer() {
    Ok(tracer) -> process.send(tracer, Record(span))
    Error(Nil) -> Nil
  }
}

/// Run `work` in a span, `failed` describes a result that is a failure.
pub fn span(
  name: String,
  parent: Option(Context),
  attributes: List(#(String, Attribute)),
  work: fn(Context) -> a,
  failed: fn(a) -> Option(String),
) -> a {
  let open = start(name, parent, attributes)
  let result = work(context(open))
  end(open, [], failed(result))
  result
}

pub fn text(value: String) -> Attribute {
  span.Text(value)
}

pub fn int(value: Int) -> Attribute {
  span.Integer(value)
}

pub fn bool(value: Bool) -> Attribute {
  span.Boolean(value)
}

fn id(bytes) {
  crypto.strong_random_bytes(bytes)
  |> bit_array.base16_encode
  |> string.lowercase
}

/// The most recent spans, newest first.
pub fn recent(limit: Int) -> List(span.Span) {
  case tracer() {
    Ok(tracer) -> process.call(tracer, 5000, Recent(limit, _))
    Error(Nil) -> []
  }
}

type Exporter {
  Exporter(
    url: String,
    headers: List(#(String, String)),
    service: String,
    failed: Bool,
  )
}

type State {
  State(
    self: Subject(Message),
    recent: List(span.Span),
    pending: List(span.Span),
    exporter: Option(Exporter),
  )
}

/// Start the cloud's tracer, configured by the standard OpenTelemetry variables.
pub fn start_tracer() -> Result(Subject(Message), actor.StartError) {
  let exporter = exporter()
  actor.new_with_initialiser(1000, fn(self) {
    process.send_after(self, 2000, Flush)
    State(self:, recent: [], pending: [], exporter:)
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) {
    set_tracer(started.data)
    started.data
  })
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Record(span) -> {
      let recent = [span, ..state.recent] |> list.take(keep)
      let state = State(..state, recent:)
      case state.exporter {
        None -> state
        Some(_) -> {
          let state = State(..state, pending: [span, ..state.pending])
          case list.length(state.pending) >= batch {
            True -> export(state)
            False -> state
          }
        }
      }
      |> actor.continue
    }
    Flush -> {
      process.send_after(state.self, 2000, Flush)
      export(state) |> actor.continue
    }
    Recent(limit:, reply:) -> {
      process.send(reply, list.take(state.recent, limit))
      actor.continue(state)
    }
  }
}

fn export(state: State) -> State {
  case state.exporter, state.pending {
    None, _ | _, [] -> state
    Some(exporter), pending -> {
      let body =
        trace.encode(exporter.service, "eyg", [], list.reverse(pending))
        |> json.to_string
      let sent = {
        use request <- result.try(
          request.to(exporter.url) |> result.replace_error("invalid url"),
        )
        let request =
          request
          |> request.set_method(http.Post)
          |> request.set_header("content-type", "application/json")
          |> request.set_body(body)
        let request =
          list.fold(exporter.headers, request, fn(request, header) {
            request.set_header(request, header.0, header.1)
          })
        httpc.configure()
        |> httpc.timeout(2000)
        |> httpc.dispatch(request)
        |> result.map_error(string.inspect)
        |> result.try(fn(response) {
          case response.status {
            200 | 202 -> Ok(Nil)
            status -> Error("collector returned " <> string.inspect(status))
          }
        })
      }
      let exporter = case sent, exporter.failed {
        Ok(Nil), _ -> Exporter(..exporter, failed: False)
        Error(reason), False -> {
          // Report once until an export succeeds again.
          io.println_error("trace export failed: " <> reason)
          Exporter(..exporter, failed: True)
        }
        Error(_), True -> exporter
      }
      State(..state, pending: [], exporter: Some(exporter))
    }
  }
}

fn exporter() -> Option(Exporter) {
  let disabled =
    envoy.get("OTEL_SDK_DISABLED")
    |> result.map(string.lowercase)
    == Ok("true")
  let url = case envoy.get("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT") {
    Ok(url) -> Ok(url)
    Error(Nil) ->
      envoy.get("OTEL_EXPORTER_OTLP_ENDPOINT")
      |> result.map(fn(base) {
        case string.ends_with(base, "/") {
          True -> base <> "v1/traces"
          False -> base <> "/v1/traces"
        }
      })
  }
  case disabled, url {
    False, Ok(url) -> {
      let headers =
        envoy.get("OTEL_EXPORTER_OTLP_TRACES_HEADERS")
        |> result.lazy_or(fn() { envoy.get("OTEL_EXPORTER_OTLP_HEADERS") })
        |> result.map(parse_headers)
        |> result.unwrap([])
      let service = envoy.get("OTEL_SERVICE_NAME") |> result.unwrap("eyg-cloud")
      Some(Exporter(url:, headers:, service:, failed: False))
    }
    _, _ -> None
  }
}

/// `key=value` pairs separated by commas, values are percent encoded.
pub fn parse_headers(text: String) -> List(#(String, String)) {
  string.split(text, ",")
  |> list.filter_map(fn(pair) {
    use #(key, value) <- result.map(string.split_once(pair, "="))
    #(
      string.trim(key),
      uri.percent_decode(string.trim(value)) |> result.unwrap(value),
    )
  })
}

@external(erlang, "cloud_ffi", "set_tracer")
fn set_tracer(tracer: Subject(Message)) -> Nil

@external(erlang, "cloud_ffi", "get_tracer")
fn tracer() -> Result(Subject(Message), Nil)
