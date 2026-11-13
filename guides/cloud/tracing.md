---
name: Tracing the cloud
description: Every EYG program and every effect it performs as OpenTelemetry spans, read in the cloud or sent to a collector.
---

# Tracing

The cloud traces at the language level: every EYG program run is an `eyg.run` span,
and every effect it performs is an `eyg.effect.<Name>` span inside it.
Function calls are not traced, they are too fine grained to be useful yet.

| Span | Inside | Attributes |
| --- | --- | --- |
| `eyg.cloud.invocation` | | `eyg.cloud.channel`, `eyg.cloud.author`, an `eyg` code block posted in a channel |
| `eyg.cloud.trigger` | | `eyg.trigger.name`, `eyg.trigger.event`, `eyg.cloud.channel`, recorded when the pattern matched |
| `eyg.agent.turn` | a session, or the `Delegate` effect for subagents | `eyg.cloud.location`, `gen_ai.request.model` |
| `eyg.llm.completion` | `eyg.agent.turn` | `gen_ai.request.model` |
| `eyg.cloud.web` | | `eyg.cloud.user`, `eyg.cloud.binding`, a web shell cell or an HTTP API call |
| `eyg.cloud.configuration` | | `eyg.cloud.file`, evaluating `workspace.eyg` |
| `eyg.run` | any of the above | |
| `eyg.effect.<Name>` | `eyg.run` | `eyg.effect.name`, `eyg.policy.decision` |

`eyg.policy.decision` is `pass` when the gate let the effect run, `mock` when the gate answered for it,
`unavailable` when the shell has no gate and `failed` when the gate itself failed.
An `Error(...)` reply marks the effect span as failed while the program continues, as on the roadmap's CLI tracing.

## Reading traces

The cloud keeps the latest 2000 spans. Read them with the `Traces` effect of the [configuration API](./api.md),
gated by a `traces` field, from the web shell, a trusted channel or `POST /api/Traces`.
The admin page draws them as trees.

```eyg
perform Traces(20)
```

## Exporting

Set the standard OpenTelemetry variables to send spans as OTLP/HTTP JSON to a collector such as Jaeger or Honeycomb.

| Variable | |
| --- | --- |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Base URL, `/v1/traces` is appended |
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | Exact URL, overrides the base |
| `OTEL_EXPORTER_OTLP_HEADERS`, `OTEL_EXPORTER_OTLP_TRACES_HEADERS` | `key=value` pairs separated by commas, values percent encoded |
| `OTEL_SERVICE_NAME` | Defaults to `eyg-cloud` |
| `OTEL_SDK_DISABLED` | `true` turns export off |

Spans are sent every two seconds or every 128 spans. A failed export is reported once and spans are dropped, there is no retry.
Span data and encoding are the portable [`otel`](../../packages/otel/README.md) package.
