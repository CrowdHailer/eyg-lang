---
name: Evaluate Overlay sessions
description: Validate task suites, grade complete agent sessions and replay recorded model exchanges.
---

# Evaluate Overlay sessions

From `packages/overlay_eval`:

```sh
gleam test
gleam run -m overlay/eval -- validate suites/fibonacci.eyg
gleam run -m overlay/eval -- run suites/fibonacci.eyg \
  --model scripted:oracle --trials 2
```

`validate` requires each reference solution to pass its deterministic checks
and an agent that does nothing to fail. The scripted run executes the references;
it checks the harness rather than a model's ability.

A task is an EYG record with `description`, `prompts`, `checks` and `reference`.
Optional fields select `tags`, virtual `workspace` files, HTTP `routes` and
`max_model_calls`. A suite maps task names to these records.

The runner uses the real web state machine against controlled guides, packages,
repository bytes and workspace files. Repository contents are frozen at setup;
hidden files, generated/dependency directories and symlinks are omitted. Requests
outside those fixtures are refused. The selected model transport is separate.

Deterministic checks cover computed values or predicates, package/context use,
responses, successful fetches and resulting workspace contents. `Judged(criterion)`
uses a model for one criterion; it reports pass, fail or unknown.

`--model` supports `ollama:<name>` (`OLLAMA_API_KEY`), `ollama-local:<name>`,
`mistral:<name>` (`MISTRAL_API_KEY`), `openai-local:<name>` and
`scripted:oracle`/`scripted:null`. Local OpenAI uses
`OVERLAY_EVAL_OPENAI_ORIGIN`, default `http://127.0.0.1:7210`.
Use `--context <module.eyg>`, `--judge <model>`, `--trials <n>`,
`--tag <tag>` or `--timeout <seconds>` as needed; timeout 0 waits indefinitely.
`--root` selects the repository and `--out` selects the report directory.

Reports include `run.json`, `summary.md` and a file per trial. They distinguish
pass@k (any trial passes) from pass^k (all pass), check results and execution/model
counts. Confidence intervals use per-task means; one task has no such interval.
`compare a/run.json b/run.json` pairs tasks across runs.
`calibrate run.json` produces a human-label template; pass that template back as
the second argument to compare judge decisions with your labels.

For a model transport, `--record <directory>` saves complete exchanges and
`--replay <directory>` reuses them. Strict replay checks method, URL, body and
stable protocol headers, excluding authentication/signing headers. An incomplete
stream is not saved as a completed reply. Older source-branch keys retain their
original method/URL/body check. Replay uses placeholder cloud credentials and
needs no API key. `--lenient` allows changed requests and
must be paired with replay. Recording and replay cannot be combined.

## Check recording and replay

```sh
gleam run -m session_check
```

This runs the actual CLI against a local HTTP fixture: two trials compute 17710,
four model requests are recorded, the fixture stops, and strict replay passes
with no further HTTP requests. It checks report files and saves the evidence in
`evidence/session-protocol`. Model-quality evidence remains separate in the
[pure evaluation guide](./pure_model_evals.md).

## Check contexts

`suites/contexts.eyg` contains 16 tasks covering package and guide discovery,
source diagnosis, program correction and workspace notes. Validate their
reference and empty-agent controls against each [context](./overlay_contexts.md):

```sh
gleam run -m overlay/eval -- validate suites/contexts.eyg \
  --context none \
  --context ../../eyg_packages/overlay_librarian/index.eyg \
  --context ../../eyg_packages/overlay_maintainer/index.eyg
gleam run -m overlay/eval -- validate suites/programs.eyg
```

The programs suite checks four computed outcomes without requiring a particular
solution. Neither validation measures model quality. Context tasks with Judged
checks still need a judge and calibration in a model run; validation checks
their deterministic criteria only.
