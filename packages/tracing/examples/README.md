# EYG tracing examples

These programs use the existing computer effects. Runtime instrumentation records
their spans automatically.

| Program | Demonstrates | Expected exit |
| --- | --- | ---: |
| [01-paced-workflow.eyg](01-paced-workflow.eyg) | Three waits of different lengths; span width is elapsed time. | 0 |
| [02-http-workflow.eyg](02-http-workflow.eyg) | Three sequential local HTTP requests; identify the slowest call. | 0 |
| [03-retry.eyg](03-retry.eyg) | HTTP 503, a 100 ms backoff, then a successful request. | 0 |
| [04-recovered-error.eyg](04-recovered-error.eyg) | A failed directory-as-file read, followed by a successful fallback. | 0 |
| [05-failed-run.eyg](05-failed-run.eyg) | An unhandled Abort marks evaluation and root as errors. | 1 |
| [06-function-profile.eyg](06-function-profile.eyg) | Named functions, real string processing, and a configurable slow effect; use `eyg profile`. | 0 |

`http.eyg` is a shared library for the two HTTP demos. `fixtures/fallback.txt` is
the recovery input. There are no remote package references or API keys.

## Run everything and regenerate the presentation

Build the CLI from `packages/gleam_cli`:

```sh
gleam build --target javascript --warnings-as-errors
```

Then, from the repository root:

```sh
docker compose -f packages/tracing/compose.yaml up -d
```

From `packages/tracing`:

```sh
gleam run -- capture
gleam run -- profile-capture
gleam run -- export
```

The capture script starts a temporary local HTTP fixture server, runs all five
EYG programs, verifies outputs, exits, span relationships, effect order, and error
statuses, and forwards their actual OTLP payloads to Jaeger. It then generates the
SVG charts and HTML presentation. `export` uses local Chrome to create a PDF
and PNG previews (`CHROME_BIN` can select another Chrome/Chromium executable).

The separate `profile-capture` command runs example 06 twice, once with
`EYG_DEMO_DELAY=0` and once with `EYG_DEMO_DELAY=120`. Both perform the same string
processing, while one waits longer inside `slow_lookup`. Open the
[performance view](../presentation/profile.html) to compare clocks, inspect frames,
zoom, and sort functions by self time. The adjacent `*.chrome.json` recordings
can also be loaded in Chrome DevTools Performance.

Open [the presentation](../presentation/index.html), [the PDF](../presentation/otel-in-eyg.pdf),
or [the measured summary](../presentation/summary.md).

## Run individual examples

Using a CLI installed from this checkout, from the repository root:

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
  eyg run packages/tracing/examples/01-paced-workflow.eyg
```

Without installing the CLI, from `packages/gleam_cli`:

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
  gleam run -- run ../tracing/examples/01-paced-workflow.eyg
```

For examples 02 and 03, first start the HTTP fixture server in another terminal,
from `packages/tracing`:

```sh
gleam run -- demo-server
```

It listens on `127.0.0.1:8787`. Set `EYG_DEMO_PORT` on both the server and the EYG
program to use another port. Stop the standalone server with Ctrl-C.

## Read the visualizations

- Purple marks root spans, amber marks host effects, and mint/blue mark function
  depths. Intrinsics are grey-blue; operational errors are pink. Short spans
  may appear as ticks.
- Flame charts preserve start time and parent depth. They are wall-clock span
  charts, not aggregated CPU flame graphs. Parent duration includes its children.
- Timeline route/status labels are matched from the fixture server's request log;
  they are not currently attributes exported by Loam.
- A `Fetch` returning an HTTP 503 response is still `Ok(response)` at the effect
  boundary. The retry example checks the HTTP status itself.
- The delays in the HTTP server are intentional fixtures. No real model is called.

The HTML deck is self-contained: scroll or use Page Up/Down to navigate,
and print for a landscape slide layout. The interactive performance view embeds
the compiled Gleam viewer; its controls also work offline.
The separate `captures.json` and `*.otlp.json` files retain the measured evidence.

To restyle charts/slides without replacing the measurements:

```sh
# From packages/tracing
gleam run -- render
gleam run -- export
```

Jaeger services are named `eyg-01-paced-workflow` through
`eyg-05-failed-run`. The presentation's saved trace data remains available
after Jaeger's seven-day retention expires.
