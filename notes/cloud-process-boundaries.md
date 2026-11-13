---
name: Cloud process boundaries
description: Why cloud processes exchange plain input data but never EYG closures.
date: 2026-11-12
---

EYG closures capture their whole environment.
Closures defined in one module capture the closures defined before them, so a module's values share most of their structure.
The BEAM flattens shared structure when a term is copied to another process.
A channel function from a small workspace configuration measured 13,769 words shared and 529,735,201 words flat,
starting a process with it exhausted memory.

The cloud package therefore sends only strings, Gleam data, subjects and native input values built as plain trees between processes. It never sends evaluated handler or policy closures.
Each process that runs EYG code evaluates the workspace configuration itself with a `config.Loader`.
Evaluating `workspace.eyg` takes milliseconds and has the benefit that configuration changes apply to the next turn without a restart.

Values from EYG programs that must cross a process boundary, for example a trigger's script, are kept as source text.
Capturing only free variables in interpreter closures would remove this restriction.
