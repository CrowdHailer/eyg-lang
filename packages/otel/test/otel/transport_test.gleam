import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import javascript/mutable_reference as ref
import otel
import otel/clock
import otel/codec
import otel/span
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server

fn receiver(status, body) {
  let requests = ref.new([])
  let assert Ok(bun) = runtime.get()
  let assert Ok(response) = fetch.get_response()
  let assert Ok(server) =
    server.serve(
      bun,
      server.Options(port: 0, hostname: "127.0.0.1", fetch: fn(request) {
        use content <- promise.map(fetch.request_text(request))
        let assert Ok(content) = content
        let _ =
          ref.update(requests, fn(items) {
            [
              #(
                fetch.request_url(request),
                fetch.request_header(request, "content-type"),
                fetch.request_header(request, "authorization"),
                content,
              ),
              ..items
            ]
          })
        let assert Ok(response) = fetch.new_response(response, body, status, [])
        response
      }),
    )
  #(server, "http://127.0.0.1:" <> int.to_string(server.port(server)), requests)
}

pub fn bounded_batches_preserve_hierarchy_status_and_timestamps_test() {
  let #(server, endpoint, received) = receiver(200, "{}")
  let exporter =
    otel.configure(
      [
        #("OTEL_EXPORTER_OTLP_ENDPOINT", endpoint <> "///"),
        #("OTEL_SERVICE_NAME", "test-service"),
        #("OTEL_EXPORTER_OTLP_HEADERS", "authorization=Basic%20test"),
      ],
      "fallback",
      "test.scope",
      [#("deployment", "local")],
    )
  let root = otel.start_span(otel.trace_id(), None, "root", [])
  let children =
    list.repeat(Nil, 260)
    |> list.index_map(fn(_, i) {
      otel.start_span(
        root.trace_id,
        Some(root.span_id),
        "child-" <> int.to_string(i),
        [],
      )
      |> otel.end_span(case i {
        0 -> Some("")
        _ -> None
      })
    })
  let root = otel.end_span(root, None)
  use exported <- promise.await(otel.export_spans(
    exporter,
    list.append(children, [root]),
  ))
  assert !exported.warned
  let requests = ref.get(received) |> list.reverse
  assert list.length(requests) == 3
  let batches =
    list.map(requests, fn(item) {
      assert item.0 == endpoint <> "/v1/traces"
      assert item.1 == Some("application/json")
      assert item.2 == Some("Basic test")
      let assert Ok(spans) = json.parse(item.3, codec.spans())
      spans
    })
  assert list.map(batches, list.length) == [128, 128, 5]
  let spans = list.flatten(batches)
  assert list.length(list.unique(list.map(spans, fn(s) { s.span_id }))) == 261
  let assert Ok(first) = list.first(spans)
  assert first.error == Some("")
  let assert Ok(last) = list.last(spans)
  assert last.error == None && last.parent_id == None
  assert list.all(spans, fn(s) {
    s.trace_id == root.trace_id
    && clock.difference(s.started, root.started) >= 0
    && clock.difference(root.ended, s.ended) >= 0
  })
  let assert Ok(_) =
    json.parse(json.to_string(otel.encode(exporter, [root])), codec.spans())
  use stopped <- promise.map(server.stop(server, True))
  assert stopped == Ok(Nil)
}

pub fn exact_endpoint_and_disabling_are_per_exporter_test() {
  let #(server, endpoint, received) = receiver(200, "{}")
  let exporter =
    otel.configure(
      [
        #("OTEL_EXPORTER_OTLP_ENDPOINT", "http://unused.invalid"),
        #("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", endpoint <> "/custom"),
      ],
      "test",
      "scope",
      [],
    )
  let disabled =
    otel.configure(
      [
        #("OTEL_EXPORTER_OTLP_ENDPOINT", endpoint),
        #("OTEL_SDK_DISABLED", "TRUE"),
      ],
      "test",
      "scope",
      [],
    )
  let span =
    otel.start_span(otel.trace_id(), None, "span", []) |> otel.end_span(None)
  use _ <- promise.await(otel.export_spans(disabled, [span]))
  assert ref.get(received) == []
  use _ <- promise.await(otel.export_spans(exporter, [span]))
  let assert [request] = ref.get(received)
  assert request.0 == endpoint <> "/custom"
  use stopped <- promise.map(server.stop(server, True))
  assert stopped == Ok(Nil)
}

pub fn http_failures_return_diagnostic_state_without_rejecting_test() {
  failure(503, "{}")
}

pub fn partial_rejection_returns_diagnostic_state_test() {
  failure(
    200,
    "{\"partialSuccess\":{\"rejectedSpans\":\"1\",\"errorMessage\":\"rejected\"}}",
  )
}

pub fn invalid_response_returns_diagnostic_state_test() {
  failure(200, "invalid json")
}

fn failure(status, body) {
  let #(server, endpoint, _) = receiver(status, body)
  let exporter =
    otel.configure(
      [#("OTEL_EXPORTER_OTLP_ENDPOINT", endpoint)],
      "test",
      "scope",
      [],
    )
  let span =
    otel.start_span(otel.trace_id(), None, "span", []) |> otel.end_span(None)
  use exporter <- promise.await(otel.export_spans(exporter, [span]))
  assert exporter.warned
  use repeated <- promise.await(otel.export_spans(exporter, [span]))
  assert repeated.warned
  use stopped <- promise.map(server.stop(server, True))
  assert stopped == Ok(Nil)
}

pub fn otlp_attributes_and_millisecond_archives_encode_without_loss_test() {
  assert clock.encode(clock.from_milliseconds(1_791_912_345_123))
    == "1791912345123000000"
  assert json.to_string(
      span.value_json(span.Array([span.Text("a"), span.Integer(7)])),
    )
    == "{\"arrayValue\":{\"values\":[{\"stringValue\":\"a\"},{\"intValue\":\"7\"}]}}"
}
