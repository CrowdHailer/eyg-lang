---
name: Tracing EYG execution
description: Record effect spans and named function profiles locally or send OTLP to a collector.
---

# Tracing EYG execution

Run these commands from `packages/gleam_cli` to use this checkout:

```sh
EYG_PROFILE_FILE=/tmp/eyg-effects.json \
  gleam run -- run -c 'perform Sleep(10)'

EYG_PROFILE_FILE=/tmp/eyg-functions.json \
  gleam run -- profile -c 'let wait = (_) -> { perform Sleep(10) } wait({})'
```

Open Chrome **Performance → Load profile** and choose the JSON file. Expand
the **EYG evaluation** track. The output directory must already exist.
An installed CLI accepts the same arguments as `eyg run` and `eyg profile`.

To send OTLP/HTTP JSON, set `OTEL_EXPORTER_OTLP_ENDPOINT` to a collector base
URL such as `http://localhost:4318`. EYG appends `/v1/traces`.
`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` supplies an exact URL instead.
`OTEL_SERVICE_NAME` changes the service name (default `eyg`). Header lists use
the standard `OTEL_EXPORTER_OTLP_HEADERS` or trace-specific
`OTEL_EXPORTER_OTLP_TRACES_HEADERS`; values are percent encoded.
`OTEL_SDK_DISABLED=true` disables both network export and local profiles.

Ordinary runs record `eyg.run → eyg.eval → eyg.effect.<name>`. Only effects
dispatched to the host appear here. An `Error` reply marks its effect as failed
while allowing the caller to recover. Errors and process exits close open spans.
Completed spans stream in batches of at most 128, with a two-second request
timeout. Failed export reports once per run and preserves the program result.

`profile` additionally records every callable application, including builtins,
callbacks, module initializers and handlers. Function names follow definitions
through aliases. EYG is curried, so two arguments produce two unary spans.
Recursive frames and continuation segments retain their ancestry;
`eyg.profile.call_id` joins segments and `eyg.profile.resumed` marks re-entry.

These are instrumented wall times. `eyg.profile.self_ns` excludes immediate
children, `effect_ns` counts descendant host-effect time once, and `active_ns`
subtracts that effect time. Remaining time includes interpreter work, scheduling,
garbage collection and recording overhead. Profiles retain spans in memory and
export after measurement ends; ordinary effect tracing exports during the run.

Gleam hosts can wrap lazy work with
`system.span(name, attributes, fn() { work }, error_callback)`. Return
`Some(message)` from the callback for a failure, or `None` for success. Run with
`system.run`; `system.run_with_environment` supplies explicit per-run settings.
The in-memory sandbox ignores these host observation markers.

From `packages/otel`, `packages/loam`, and `packages/gleam_cli`, validate with:

```sh
gleam format --check src test
gleam build --warnings-as-errors
gleam test --runtime bun
```

The Gleam tests run HTTP receivers and actual CLI processes. They cover
batching, ancestry, failures, exit flushing, disabled export, local output,
recursion, continuation resumption, import purity and profiling time boundaries.
