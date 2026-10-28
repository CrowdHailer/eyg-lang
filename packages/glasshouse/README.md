# Glasshouse

Portable trajectory archives for EYG and Overlay. `recorder` canonically stores
effect inputs/replies and large binaries as content-addressed DAG-JSON blocks.
`run` keeps pinned programs, source locations, outcomes and ordered journals;
`session` adds prompts, model requests/responses, usage and tool results.
`archive` retains the complete referenced block closure in one JSON document.

`replay` verifies effects in order, and `rerun` executes recorded programs
against those replies without the original files or hub. `timeline` can show
observed file changes; it is not a complete snapshot of unobserved host state.
The sandbox attachment is an immutable root for complete environments and
external observations. `bundle.validate` checks both hashes and closure.

`telemetry` produces standard OTLP spans through the shared `otel` codec, with
standard model/token attributes and optional Langfuse metadata. `langfuse`
provides its authentication request and trace link. State remains in the
archive and is linked by CID; it is not uploaded as telemetry.

Synchronous browser SHA-256 is implemented in Gleam. Host callers can supply
native hashing through `store.Sha256`. Recording redacts registered plaintext
secrets; transformations of those values are not automatically recognized.
Keep credentials outside model context and portable environments.

Run `gleam format --check src test`, `gleam build --warnings-as-errors`, and
`gleam test --runtime bun` in this directory. Tests cover canonical encoding,
deduplication, archive closure, replay divergence, secrets, context, file diffs,
usage, OTLP hierarchy and SHA-256 vectors/padding against native cryptography.
