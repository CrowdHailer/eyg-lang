---
name: Start Overlay from scripts
description: Start a typed agent context and ask the type checker from an EYG script.
---

# Start Overlay from scripts

`eyg run` and `eyg script` support two CLI effects:

| Effect | Input | Result |
| --- | --- | --- |
| TypeCheck | EYG source text | Ok(type text) or Error(parse/type errors) |
| Overlay | A record of llm, policy and context | Ok({}) when the conversation ends, or Error(reason) |

These host capabilities let a project's script check generated configuration
and enter an agent session. Ordinary EYG functions cannot invoke the host's
type checker or terminal agent loop. The effects are unavailable to agent
programs and sealed sandboxes.

From the repository root:

```sh
eyg run -c 'match perform TypeCheck("!int_add(20, 22)") { Ok(type_) -> { perform StandardOut(type_) } Error(reason) -> { !never(perform Abort(reason)) } }'
eyg script examples/overlay_script/entry.eyg
```

The first command prints Integer. The example checks a program, starts an agent
with `context.twice(integer)`, then resumes its script after empty input or EOF.
It uses a local Ollama endpoint; set EYG_AGENT_MODEL_ORIGIN and EYG_AGENT_MODEL
to select an available server and model.

The context's functions are checked with their captured variables before any
prompt is read. Used continuations cannot be captured. Lazy imports inside
functions keep their defining file's directory; TypeCheck source imports use the
invocation directory. The config structure is decoded at runtime, while the
context is inferred; this entry does not statically check policy gate types.

Each agent turn gets the usual [trajectory](./trajectories.md). Its configuration
is a pinned context snapshot with provider credentials redacted. Earlier IO by
the calling script is outside that snapshot.

The CLI captured-effect and script-agent tests check returned values, type errors, refusal, and recorded execution.
