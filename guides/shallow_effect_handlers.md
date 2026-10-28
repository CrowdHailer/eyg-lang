---
name: Shallow handlers
description: Raw resumptions, independent answer types, and explicit reinstallation.
---

# Shallow handlers

Read [deep handlers](./deep_effect_handlers.md), [stateful handlers](./advanced_effects.md),
and [masking](./masking_effects.md) first. Ordinary `handle E` remains deep.

```eyg
handle shallow Ping(
  (request, resume) -> { 42 },
  (value) -> { !string_length(value) },
  (_) -> { "hello" }
)
// 5
```

Arguments are operation callback, normal-return callback, then body. The body
runs with `{}`. On an operation, the raw continuation excludes the matching
handler and its return callback. Normal completion while the handler is installed
calls the return callback; the operation callback's answer bypasses it.

Both callbacks run outside the delimiter. Other captured inner handlers remain
in the continuation. Resumptions are immutable and multi-shot.

## Choosing the next handler

```eyg
let resume = handle shallow Ping((_, resume) -> { resume },
  (value) -> { (_) -> { value } }, (_) -> {
    let a = perform Ping({})
    let b = perform Ping({})
    !int_add(a, b)
  })
handle Ping((_, resume) -> { resume(100) }, (_) -> { resume(1) })
// 101
```

A state runner can install an updated handler before resuming. See
[`shallow_state.eyg`](./examples/shallow_state.eyg). Independently nested handlers
still do not share changing state automatically; use a combined state protocol.

## Types and normal return

For body result `B`, handled answer `A`, request `P`, and reply `Q`:

```text
body:      {} -> <E(P,Q) | e> B
resume:     Q -> <E(P,Q) | e> B
operation:  P -> (resume -> e A)
on_return:  B -> e A
result:     A, with effects e
```

`A` and `B` are independent. This permits a finite answer such as
`{lift: P, resume: Q -> B}`. A raw resumption still requires a handler for `E`;
dropping that label from its type would admit unhandled operations.

The current scoped-row signature is conservative about directly forwarding a
raw continuation inside its own operation callback: it can require
`e = <E | e>`. Returning the continuation and running it under a new handler,
or explicitly reinstalling the handler recursively, avoids that constraint.
`mask` changes routing; it is not permission to remove an effect from a raw
continuation's type. The direct-forwarding restriction has a regression test.

## Implementation and verification

The IR node `Shallow(label)` uses `{"0":"hs","l":"E"}`. Existing deep
encodings are unchanged. `spec/shallow_handlers.json` is shared by inference,
interpreter, and compiler tests. Additional tests cover state, tail-space bounds
and multi-shot replay.

[`deep_from_shallow.eyg`](./examples/deep_from_shallow.eyg) demonstrates recursive
reinstallation as an encoding of deep handling. This example does not imply that
a shallow-only core has all the same inference or space guarantees.

From the repository root:

```sh
eyg eval guides/examples/shallow_state.eyg
eyg eval guides/examples/deep_from_shallow.eyg
```

These return `{state: 1, value: [0, 2, 1]}` and 2.
