---
name: Saving and replaying trajectories
description: Save portable execution journals and export their observability to OpenTelemetry backends.
---

# Saving and replaying trajectories

From `packages/gleam_cli`, record a block with the CLI from this checkout:

```sh
EYG_TRACE_DIR=/tmp/eyg-trajectories \
  gleam run -- record run -c 'perform StandardOut("hello\n")'
```

The command prints the saved JSON path. Substitute that path below:

```sh
gleam run -- inspect /tmp/eyg-trajectories/<session>.json
gleam run -- replay /tmp/eyg-trajectories/<session>.json
```

An installed checkout accepts the same arguments as `eyg record`, `eyg inspect`
and `eyg replay`. `record run <file>` records a block; `record <file> [args...]`
records a module's `script` function. Archives default to `.eyg/traces` under
the invocation directory. Failed executions are saved with their outcome.

Each archive contains a session, ordered runs/effect journals, a pinned module
lock, outcomes, and the reachable DAG-JSON blocks keyed by CID. File values and
large binaries are deduplicated. Replay runs the pinned programs and checks
effect order, requests, replies and outcomes using the archive. Ordinary replay
does not perform recorded writes or HTTP requests. `inspect <trace> <step>`
shows observed filesystem changes at that zero-based effect position.

This records observations of the host. Unobserved files and external service
state are not a full environment snapshot. Complete environment replay belongs
to the sandbox workflow. Legacy `.env.eyg` imports are intentionally unstored
and need a matching local source for replay. Credential-like `Env` values are
redacted and locked by hash; changed credentials use placeholders and can make
an execution that depends on secret contents diverge.

## Storage comparison

The comparison follows the pi-mono and opencode snapshots reviewed on
`bot/harnesses` (`6d7d0efe`):

| Format | Structure | Reproduction state |
| --- | --- | --- |
| pi-mono | Version 3 JSONL: session header followed by entries with IDs and parent IDs; append-only branches, messages, model/thinking changes, compaction and custom entries. | Reconstructs the selected conversation branch; filesystem and service replies are not an EYG effect journal. |
| opencode | SQLite session/message/part records; exported JSON uses `{info, messages}`, with each message containing `{info, parts}` and tool results in tool-part state. | Stores chat/tool history and associated metadata; its export does not provide EYG's pinned code and complete effect-reply closure. |
| Glasshouse | Versioned JSON session plus CID-indexed DAG-JSON blocks, ordered effects and module locks. | Re-executes EYG against recorded replies; a sandbox attachment adds complete immutable inputs/outputs and external observations. |
| OTLP | Resource/scope spans with trace/span IDs, parents, exact decimal-string epoch nanoseconds, attributes and status. | Carries observability and archive pointers; it is not the portable replay archive. |

Overlay's opencode export is a conversation interchange view. Glasshouse keeps
the execution evidence separately. The original chat-only export uses export
time for timestamps; trajectory archives retain actual event/run timings.

## Upload telemetry

For a standard OTLP/HTTP collector:

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
  gleam run -- upload /tmp/eyg-trajectories/<session>.json
```

The exact traces endpoint, headers and service name follow the settings in the
[tracing guide](tracing.md). Exported state is represented by CIDs, while model
and tool summaries are telemetry. The archive remains the source for replay.

For Langfuse:

```sh
LANGFUSE_HOST=http://localhost:3000 \
LANGFUSE_PUBLIC_KEY=pk-lf-eyg-local \
LANGFUSE_SECRET_KEY=sk-lf-eyg-local \
  gleam run -- upload /tmp/eyg-trajectories/<session>.json
```

With both keys configured, upload uses Basic authentication at
`/api/public/otel/v1/traces`, sends `x-langfuse-ingestion-version: 4`, and adds
a trace link to the archive after acceptance. A partial rejection fails upload.
`gen_ai.request.model`, `gen_ai.operation.name`, `gen_ai.provider.name` and
token counts are standard attributes. `langfuse.trace.*`, `langfuse.session.id`
and `langfuse.observation.*` supply Langfuse's names, tags, session grouping,
generation/tool classifications, input/output summaries and metadata.
See [Langfuse's OTLP integration](https://langfuse.com/integrations/native/opentelemetry)
and [v4 ingestion requirements](https://langfuse.com/integrations/native/opentelemetry/migration-to-v4).
