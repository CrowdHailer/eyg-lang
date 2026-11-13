---
name: Exporting compiled EYG modules
description: Import compiled programs and answer their effects from a JavaScript host.
---

# Exporting compiled EYG modules

`eyg/compiler.to_module(source, reference_types)` checks a closed program and
returns an ES module as a string, or inference errors. Parse text with
`eyg/parser.all_from_string` first. Inline imports before compiling: reference
types supply checking information, not executable module bodies.

The default export has four members:

| Member | Use |
| --- | --- |
| program | The program's value, callable function or first suspended host operation |
| run(value, handlers) | Resume with synchronous callbacks keyed by effect label |
| runAsync(value, handlers) | Await each host reply before continuing |
| Eff | Constructor for inspecting a suspended operation's label, value and continuation |

Importing the module does not call host handlers. A function-valued program is
called with an argument before passing its result to `run` or `runAsync`.
Suspended continuations can be resumed independently more than once. The host
owns the callbacks and must return values matching the inferred effect types.
Only a handler object's own callable properties are accepted.

Deep and shallow handlers, masks and `!pure` use the same Gleam continuation
machine as ordinary compiled execution. A host suspension keeps the active
continuation, including shallow normal-return clauses. Runtime boundaries apply
before host dispatch. Unhandled operations fail; asynchronous callback failures
reject the returned promise.

From packages/gleam_compiler:

```sh
gleam run --runtime node -m compiled_module
gleam test --runtime node
gleam test --runtime bun
```

The [executable example](../packages/gleam_compiler/dev/compiled_module.gleam)
writes `build/exported/program.mjs`, imports it, waits for a native host callback
and checks 42. Tests also check import-time suspension, callable exports,
repeated resumption, local handlers, invalid code and inherited-handler rejection.
No separate runtime package is needed by the emitted module: its runtime is a
generated bundle of [Gleam source](../packages/gleam_compiled_runtime/).
