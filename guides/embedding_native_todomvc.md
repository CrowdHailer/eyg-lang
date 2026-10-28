---
name: A todo host using the native API
description: Consume the standalone JavaScript shell with plain task data.
---

# A todo host using the native API

[examples/todomvc_native](../examples/todomvc_native/) uses the standalone
[JavaScript API](./embedding_javascript.md). Its host logic and Lustre view
are Gleam; the boundary is the same native API available to TypeScript hosts.
The HTML entry only imports and starts the compiled page.

`native/run.start_at` imports the built eyg.mjs, calls `createShell` with a
plain effects object and the todos library, and retains the returned object.
Each run calls its `run` method with ordinary host functions. Tasks cross as
records with native booleans; result replies use `$: "Ok"` or
`$: "Error", value: {$: "NotFound"}`. The SDK checks both program and replies.

The page and its agent share one shell and task list. ListTasks, CreateTask,
RenameTask, SetCompleted and Print are offered to EYG. Deletion remains in the
page's controls. Native callbacks use the same task model as the
[direct Gleam embedding](./embedding_todomvc.md), without passing interpreter
values across the bundle boundary. The shared one-tool agent owns no task access.

Build the SDK and install the shared stylesheet:

```sh
cd packages/embed_js
bun install
gleam run -m build
cd ../../examples/todomvc_lustre
bun install
cd ../todomvc_native
gleam test
gleam test --runtime node
gleam run -m dev
```

Open http://127.0.0.1:7821. Run `todos.tagged("#shopping")` in the shell, then
`todos.add("Book a taxi #travel")`. Control/Command+Enter runs the editor.
The Agent tab uses one run tool against the same state. EYG_HUB and
OLLAMA_ORIGIN select the hub and local model origins; defaults are eyg.run and
127.0.0.1:11434. Rebuild and restart after editing source.

The library pins standard's release and CID. The SDK owns the package cache
inside the shell object. Keeping that object reuses loaded values and types;
creating a new one starts a separate cache.

The browser integration check
exercises typed runs, retained bindings, native controls and an agent correcting
an invalid call. A scripted model fixture supplies the responses; this is a
protocol and integration check. A real local HTTP hub serves the committed
standard module in three requests, reused by all subsequent runs.
From packages/tracing, recreate it with
`CHROME_BIN=/path/to/chromium gleam run -m tracing/todo_native_demo`.
The driver builds the app and SDK and stops the services it starts.
