## Record a local run

Use the CLI built from this checkout until these commands are released:

```sh
# from packages/gleam_cli
gleam run -- record run -c 'perform StandardOut("hello\n")'
```

The command prints its archive path, normally under `.eyg/traces`.
`record run <file>` runs a block; `record <file> [args...]` runs a module's
`script` function. Failed executions retain their outcome.

## Record in Overlay

Choose a provider, model and token, then send a prompt. The Trace panel records
model requests, streamed replies, EYG tool runs and their effects. Select
**Download** to save one portable JSON archive. A new chat starts a new trace;
conversation history restored from tab storage predates that recording.

An EYG tool can read the earlier trajectory with `perform Trace({})`.
This effect exposes recorded state to the agent; it does not make network
requests. A stopped generation is retained as an error, while unfinished tool
executions have no completed journal.

## Inspect and replay

```sh
gleam run -- inspect .eyg/traces/<session>.json
gleam run -- replay .eyg/traces/<session>.json
```

Open the archive in the [debugger](/glasshouse/debugger). Select a moment to see
the request, reply, model context and observed filesystem changes. Arrow keys
and the scrubber move through the timeline. Select **Replay**, then the archive's
replay button to reproduce its pinned runs. Reading and replaying an uploaded
archive happens in your browser.

The bundled newsletter traces are historical fixtures from development. Their
old service effect labels are inspection data; they are not effects provided
by the current host runtime. Recorded replies allow those runs to replay.

## Upload telemetry

For a standard OTLP/HTTP collector:

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
  gleam run -- upload .eyg/traces/<session>.json
```

For Langfuse:

```sh
LANGFUSE_HOST=http://localhost:3000 \
LANGFUSE_PUBLIC_KEY=pk-lf-eyg-local \
LANGFUSE_SECRET_KEY=sk-lf-eyg-local \
  gleam run -- upload .eyg/traces/<session>.json
```

Langfuse uses Basic authentication at `/api/public/otel/v1/traces` and the v4
ingestion header. Standard `gen_ai.*` attributes carry model and token usage;
`langfuse.*` attributes add observation types, trace names, session grouping and
input/output summaries. Accepted uploads add a trace link to the archive.

## Archive format

For complete environment inputs, use the [sandbox guide](/guides/sandbox).
The [sealed sandbox example](/glasshouse/debugger?demo=sandbox) includes an
unchanged fork, a changed skill, a changed prompt and a refused external host.
`eyg sandbox replay` checks the complete environment and ordered model/network
observations; the browser's Replay panel checks each recorded EYG run.

A session holds ordered runs and events. Runs contain the source, pinned program,
module lock, effect journal and outcome. Values are DAG-JSON blocks indexed by
CID, so repeated file and binary values are stored once. The versioned JSON
archive contains the session and its reachable blocks.

Journal answers distinguish host execution, policy gates, altered requests and
mocked replies. An altered request is fingerprinted; the agent's original request
is preserved. Replay checks effect order, requests and final outcomes.

This is a recording of observed state. It does not capture files and services
that were never read. Credential-like environment values are redacted and locked
by hash. Legacy `.env.eyg` imports need a matching local file for replay.

See the [trajectory guide](/guides/trajectories) for storage comparisons with
pi-mono and opencode, backend setup and the checked browser recording.
