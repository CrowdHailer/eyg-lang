# Otel

Portable OpenTelemetry span data and OTLP/HTTP JSON encoding, with no transport and no dependency on EYG.
Hosts own context, buffering and export: the cloud exports from the BEAM in `cloud/tracing`.

- `otel/span` spans, attributes and their OTLP JSON.
- `otel/trace` a request body of spans with the resource and scope.
- `otel/clock` times as epoch seconds and nanoseconds, kept apart so JavaScript integers stay precise.

The span model and encoding follow the OTLP export started on the roadmap branch,
whose JavaScript exporter can build on these modules.
