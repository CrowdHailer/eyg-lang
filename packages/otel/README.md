# Otel

The small OTLP/HTTP JSON trace transport used by Loam. It targets JavaScript on
Node or Bun and has no dependency on EYG or its interpreter.

All trace data, configuration, encoding, batching, and error handling are Gleam.
Native high-resolution time, Fetch, and AbortSignal bindings live in `plinthx`
and follow its Plinth guidelines. Timestamps keep seconds and nanoseconds
separate so JavaScript's integer precision cannot round epoch nanoseconds.

`otel.exporter(service, scope, attributes)` reads configuration once. Create a
trace ID with `otel.trace_id()`, start spans with explicit optional parent IDs, close them
with `otel.end_span`, and send completed spans using `otel.export_spans`.
The host owns context, nesting, buffering, and lifecycle. Loam provides those
through `system.span` and `system.run`.

Supported configuration:

- `OTEL_EXPORTER_OTLP_ENDPOINT`: base URL, with `/v1/traces` appended.
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`: exact URL, overriding the base URL.
- `OTEL_SERVICE_NAME`: overrides the supplied default service name.
- `OTEL_EXPORTER_OTLP_HEADERS`: comma-separated, percent-encoded header values;
  `OTEL_EXPORTER_OTLP_TRACES_HEADERS` overrides these for traces.
- `OTEL_SDK_DISABLED=true`: disables export (case-insensitive).

Requests contain at most 128 spans and time out after two seconds. Export errors
and partial rejection produce one diagnostic per exporter; they do not reject
the export promise. There is no retry queue. Spans and exporters are immutable
Gleam records: `end_span` returns the closed span, and `export_spans` returns the
exporter with updated diagnostic state. Attributes support text, integers,
booleans, floating point values and arrays.

This implements the project's trace-export needs only: no metrics, sampling,
context propagation, or full SDK configuration. Chrome traces and EYG profiling
belong to Loam.

## Why not opengleametry?

[opengleametry 2.0.0](https://opengleametry.hexdocs.pm/2.0.0/index.html) was reviewed.
Its span API is implemented exclusively with Erlang externals and depends on
`opentelemetry_api` for the BEAM. It has no JavaScript implementation, so it cannot
instrument Loam's JavaScript/Bun interpreter. This package covers that runtime's
small trace-export needs without introducing a second runtime.

Check with `gleam build --warnings-as-errors` and `gleam test --runtime bun`.
The Gleam tests exercise a real Bun HTTP receiver, including batching, headers,
endpoint selection, failures and partial rejection.
