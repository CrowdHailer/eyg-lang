---
name: Agents in an embedded shell
description: Give an agent the same typed scripting capabilities as a person.
---

# Agents in an embedded shell

`eyg/embed/agent` exposes one model tool, `run(code)`. It is a pure protocol
module: the host sends requests, supplies response bytes, and owns execution.
The [retained shell](./embedding_in_gleam.md#retained-shell) can be shared by a
person and the agent. It checks the entire program against the offered effects
before running anything.

1. Create `agent.new(llm, system_prompt)` with an `overlay_llm` provider.
2. `agent.ask(agent, message)` returns updated history and an HTTP request.
3. Send that request in the host; check its HTTP status before passing the full
   response body to `agent.respond` or `respond_async`.
4. `Continue` contains the next request, updated state and each executed program's
   report. `Answered` contains the final text; `Failed` contains a reason.

`agent.run_in_shell(handler)` adapts `(shell, host_state)` to the synchronous
runner. For asynchronous hosts, pass `respond_async` a function that calls
`shell.run_async` and returns the updated shell, state and `shell.report`.
The host retains these returned values between calls.

The model cannot invoke host operations directly. Unknown tools and missing
code become tool reports without running code. Multiple calls run in order.
Type errors are reported for correction while preserving the previous shell.
Malformed or empty responses fail; provider terminal validation runs before tools.

`with_limit(agent, n)` bounds model round trips that execute tools, default 20.
It counts a batch as one round trip. `ask` starts a new turn and resets that
counter. The host owns request deadlines, cancellation and any run limits.

From packages/gleam_embed:

```sh
gleam run --runtime node -m host_agent
gleam test --runtime node
```

The [executable example](../packages/gleam_embed/dev/host_agent.gleam) feeds
deterministic Ollama protocol messages, checks an agent-defined `n = 5`, then
checks a person's subsequent expression returning 6 in the same shell.
It does not contact a model service. Tests also cover refused tools, provider
failures, step limits and ordered asynchronous execution on Node and Bun.
