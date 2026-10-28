---
name: Querying a todo list with EYG
description: Script a TodoMVC model through a deliberately limited typed interface.
---

# Querying a todo list with EYG

[examples/todomvc_lustre](../examples/todomvc_lustre/) gives the same todo model
to the host and an EYG shell. Programs can create, rename and complete tasks.
Deleting remains a host operation and is rejected by the script's type checker.

| Effect | Request | Reply |
| --- | --- | --- |
| ListTasks | {} | List({id, title, completed}) |
| CreateTask | String | Integer id |
| RenameTask | {id, title} | Ok({}) or Error(NotFound({})) |
| SetCompleted | {id, completed} | Ok({}) or Error(NotFound({})) |
| Print | String | {} |

The [EYG library](../examples/todomvc_lustre/library.eyg) is in scope as `todos`.
It adds case-insensitive matching, tags, active/completed queries and task helpers:

```eyg
let {list} = @standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja
list.map(todos.tagged("#shopping"), todos.complete)
```

This completes all matching tasks through SetCompleted. A missing task returns
NotFound to the program. `perform DeleteTask(1)` fails before execution.

`todomvc/run.start(library, cache)` prepares the retained shell; `run.run` takes
that shell, the current task model and source. Its result contains updated
bindings, tasks, printed lines and the execution outcome. The host keeps these
returned values so a person and an agent can work with the same state.

The library pins standard version 1 and its CID. The host owns the hub cache
and passes cached module values and types to the shell. Reusing it retains
standard's evaluated value and type; retaining the shell also retains the
checked todos helpers. Recreating both starts fresh.

From examples/todomvc_lustre, run `gleam test` and `gleam test --runtime node`.
The tests use the repository's committed standard IR and verify its CID before
caching it. They check querying, changes, unavailable operations, missing tasks
and retained shell behavior without a network service.

## Browser shell and agent

```sh
cd examples/todomvc_lustre
bun install
gleam test
gleam run -m dev
```

Open http://127.0.0.1:7820. The Lustre UI supports adding, toggling, filtering,
editing, deleting and clearing tasks. The Shell tab checks EYG before execution;
Control/Command+Enter runs its editor. The Agent tab uses the same shell and
task model, with one `run` tool. A type error is returned to the model for
correction. Native deletion remains available even though scripts cannot use it.

The Gleam development server builds the browser module and proxies `/packages/`
and `/modules/` to EYG_HUB, default https://eyg.run, and `/api/` to OLLAMA_ORIGIN,
default http://127.0.0.1:11434. Configure a running model or choose a provider
in the page. Rebuild and restart the server after changing source.

The browser integration check runs the
guide's queries, rejects wrong types and unavailable file access, and exercises
native task controls. Its agent corrects a deliberately invalid first call.
It uses an explicitly scripted model fixture, with no paid or live model call.
The real HTTP hub fixture serves the committed standard IR: three requests
load the release and module; later person and agent runs reuse it unchanged.

Recreate the recording from packages/tracing with
`CHROME_BIN=/path/to/chromium gleam run -m tracing/todo_demo`.
The driver builds the example, starts its local fixtures and app, checks the
workflow, records it, then stops all services it started.
