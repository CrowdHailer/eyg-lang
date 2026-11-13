---
name: Embedding in JavaScript hosts
description: A bundled typed shell for hosts that do not use Gleam.
---

# Embedding in JavaScript hosts

[packages/embed_js](../packages/embed_js/) builds `dist/eyg.mjs`, a standalone
ES module exporting `createShell(options)`. Its runtime, native API wrapper,
bundler and checks are authored in Gleam. The JavaScript entry only re-exports
that API; the host needs no Gleam installation or separate runtime.

From packages/embed_js:

```sh
bun install
gleam run -m build
gleam test --runtime bun
gleam test --runtime node
```

Copy `dist/eyg.mjs` and its declarations, `eyg.d.ts` or `eyg.d.mts`, into the
host application. The bundle targets browsers and also runs on Node and Bun.

`await createShell({effects, hub, modules})` returns an independent shell.
`effects` maps operation labels to request and reply type descriptors;
`hub` is an optional hub origin, and `modules` maps names to pure EYG source.
Types and values follow the [JSON boundary format](./embedding_json.md).

| Method | Behavior |
| --- | --- |
| text(module, field) | Read a string field, defaulting to readme |
| run(code, handlers) | Check and run with synchronous callbacks |
| runAsync(code, handlers) | Load references, check, then await callbacks |

Handlers are objects of functions keyed by effect label. Each receives a plain
JavaScript request value and returns the reply. Undefined replies become `{}`;
other replies must match the declared type. Use `runAsync` for promises.

Each result may contain `value`, `display` and `error`. A trailing `let` retains
its binding and returns an empty result. Functions have a display but no plain
JSON value. Parse and type failures perform no host operations. A runtime stop
retains earlier host mutations and the old successful bindings.

Overlapping async runs queue in call order and use the latest completed shell.
Synchronous runs are refused while work is pending. A thrown host callback
propagates to its caller; the shell can still run subsequent code.

Each shell owns its module cache. `runAsync` and module setup use the
[graph loader](./loading_modules.md); `run` uses only already loaded values.
Retaining the shell reuses fetched packages. Named references mean the latest
release known to that cache; pinned references provide reproducible inputs.

`gleam run -m browser_check` serves the built bundles to Chromium, checks a
real browser host callback and reuses its retained variable. Set `CHROME_BIN`
when using an existing browser binary. It stops its server and browser after
the check. All browser host logic and Playwright orchestration are Gleam.
The native test suite also checks retained bindings, lexical order, and type errors.
