---
name: Cloud process boundaries
description: Why configured workspaces exchange captured programs and plain data.
date: 2026-11-13
---

EYG closures capture their whole environment.
Closures defined in one module capture the closures defined before them, so a module's values share most of their structure.
The BEAM flattens shared structure when a term is copied to another process.
A channel function from a small workspace configuration measured 13,769 words shared and 529,735,201 words flat,
starting a process with it exhausted memory.

Configured workspaces therefore send only strings, Gleam data, subjects and native input values built as plain trees between processes. They never send evaluated handler or policy closures.
One central session actor executes all agent turns, scripts, triggers and web programs serially. Routing actors can still evaluate pure handlers; the executor evaluates its own workspace configuration with a `config.Loader`. Neither transfers evaluated configuration closures.
Evaluating `workspace.eyg` takes milliseconds and has the benefit that configuration changes apply to the next turn without a restart.

Values from EYG programs that must cross a process boundary are kept as source text,
or captured with `eyg/interpreter/capture`, which keeps only the variables a function uses, as trigger patterns and scripts are.
Capturing only free variables in interpreter closures would remove this restriction.

Basic startup automations preserve main's `trigger.prepare` and `session.Trigger`
path, which passes checked function values to the central actor. Configured
workspace closures still use the captured representation above; do not copy their
large environments into that startup path.

The web runner captures input and output values as IR before crossing the actor boundary. Commands carry explicit session IDs, plain configuration and host callbacks, never a prepared shell. Reply callbacks are independent of session identity. Only the central process looks up session state; workspaces do not keep session handles. A command applies its context and reply atomically, so a concurrent command cannot change its authority. Scheduled work retains its channel policy context and destination across web rebinding.

Main's session actor owns per-session MFS roots and histories plus the shared block store, all in memory. Programs thread filesystem state through execution and the Overlay completion loop. No session starts a filesystem actor or writes snapshots. Routing actors remain responsive so execution can call scheduling, trigger and registry services without calling into its own blocked executor. Ordinary replies and final values are direct outputs; the Post effect remains policy checked.
