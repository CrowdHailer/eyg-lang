---
name: Deep effect handlers
description: Resume effects with persistent delimiters and bounded continuation storage.
---

# Deep effect handlers

`handle E(callback, body)` runs body({}). For each E, the callback receives its
request and a continuation. It can stop, resume once or resume several times:

```eyg
handle Ping((_, resume) -> { resume(1) }, (_) -> {
  let a = perform Ping({})
  let b = perform Ping({})
  !int_add(a, b)
})
```

This returns 2. A deep resumption reinstalls its captured handler, so both
operations reach it. The callback itself runs outside that delimiter; effects
it performs reach remaining outer handlers.

From the repository root:

```sh
eyg eval guides/examples/deep_handlers.eyg
eyg eval guides/examples/stateful_handler.eyg
```

The first returns repeated/shadowed 2, forwarded 200, unrelated 12, multi_shot 6
and early_return 99. The second counts three Increment operations. See
[stateful handlers](./advanced_effects.md#stateful-handlers) for how the state moves.

A continuation captures through its matching delimiter and keeps no outer
handlers. `examples/escaping_handler.eyg` deliberately demonstrates an
unhandled Outer after that handler has returned.

The interpreter and compiler use persistent continuation stacks. Checks measure
constant stack and capture sizes through 10,000 state updates and interleaved
handlers; compiled fixed tail recursion also runs 100,000 iterations.
The compiler embeds a generated bundle of the Gleam continuation runtime.

The body and callback share an answer type. Storing the deep resumption in that
answer would require a recursive value type; return a state function instead.

Run the interpreter stateful-handler tests and compiler stack tests to recheck
these workloads against both runtimes.
