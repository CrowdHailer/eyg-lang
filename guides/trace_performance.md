---
name: Viewing execution performance
description: Capture real effect and function spans, inspect them offline and export charts or slides.
---

# Viewing execution performance

The [tracing package](../packages/tracing/) captures real CLI programs and
shares its Gleam decoder, interval layout and SVG rendering with an offline
browser viewer. The [tracing guide](./tracing.md) explains instrumentation and
the distinction between elapsed, self and host-effect time.

Build the CLI from packages/gleam_cli with gleam build. Start the local backend
from the repository root:

```sh
docker compose -f packages/tracing/compose.yaml up -d
```

Then, from packages/tracing:

```sh
bun install
gleam run -- capture
gleam run -- profile-capture
gleam run -m tracing/check_captures
gleam test
gleam test --runtime node
```

EYG_BIN can select an absolute path to a CLI built from this checkout; otherwise
the capture runs gleam run in packages/gleam_cli. Capture starts and stops its
own delayed HTTP fixtures. DEMO_JAEGER_ENDPOINT can override the receiving OTLP
URL; JAEGER_HOST selects the query API. All examples use existing effects.

Open [profile.html](../packages/tracing/presentation/profile.html) directly from
disk. Select a recording, switch between elapsed time and a clock with host
effects removed, and enable intrinsics. Click a frame for details or double-click
to focus it. Reset restores the full range; zoom widens the chart. Click a table
header to sort aggregated unary application segments. Chrome trace JSON can
also be loaded in DevTools Performance or Perfetto. The Jaeger link requires
the local service and an unexpired copy of that trace.

Host intervals are merged before subtraction, so nested effects count once.
Time outside those intervals still includes interpreter, scheduling, garbage
collection and instrumentation costs. These charts measure elapsed execution,
not sampled CPU usage or task quality.

The committed [effect summary](../packages/tracing/presentation/summary.md) and
[function summary](../packages/tracing/presentation/profile-summary.md) were
captured on 2026-10-15. Five effect examples cover paced waits, HTTP, retries,
recovery and failure. Two function recordings run the same computation with
0 ms and 120 ms requested sleeps. Their 471 spans were
[queried back from Jaeger 2.22.0](../packages/tracing/presentation/jaeger-verification.txt).
They are local fixtures and make no model calls.

To restyle the existing evidence and export printable assets:

```sh
gleam run -- render
CHROME_BIN=/absolute/path/to/chromium gleam run -- export
```

The render command generates offline HTML presentations, SVGs and OTLP files beside the source collections. Browser logic is compiled from Gleam with platform bindings in plinthx.

From packages/tracing, set CHROME_BIN if needed and run `gleam run -m tracing/performance_demo` to check the viewer's controls and frame counts. The driver owns its local static server and stops it after the check. To stop Jaeger, run docker compose -f packages/tracing/compose.yaml stop from the repository root.
