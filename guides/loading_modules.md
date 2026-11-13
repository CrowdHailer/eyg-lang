---
name: Loading module graphs
description: Drain a hub cache's fetch and release work before checking or running code.
---

# Loading module graphs

`eyg/hub/cache.load(cache, source, origin, fetch, hash, annotate)` pulls releases,
fetches content-addressed modules and follows their dependencies until no queued
work remains. It returns a continuation in the same shape as `midas/effect`.
`annotate` attaches source metadata to each fetched node.

```gleam
cache.load(cache, source, hub_origin, browser.fetch, browser.hash, fn(_) { Nil })(
  promise.resolve,
)
```

Here `browser` is `eyg/embed/browser`, and `promise` is
`gleam/javascript/promise`. Run this in a browser, Node or Bun. On the BEAM,
supply that platform's fetch and hash callbacks instead.

The host must retain the returned cache. `cache.types(loaded)` supplies module
types; `cache.get_reference(loaded, reference)` supplies an evaluated value and
its type. Use these with the [typed shell](./embedding_in_gleam.md). The loader
does not run the outer program or give its effects any host implementation.

Failures remain in the returned cache. Inspect `get_reference`, `get_module`
and the pull status before running code. A missing or corrupt module cannot
become a usable cached value. `cache.fetch` and `cache.pull` explicitly queue
retries; a failed request is not retried repeatedly within one load call.
Finish any actions already dispatched by another cache owner before using this
helper: it drains queued work and does not await someone else's requests.

Reusing a loaded graph performs no fetches or hashes. Immutable CIDs make that
reuse reproducible; `@name` means the latest release known to this cache, so
freshness requires an explicit pull. Use pinned references for a fixed release.
Cache lifetime belongs to the host.

From packages/gleam_hub, run `gleam test` and
`gleam test --target javascript --runtime node`. Checks cover release selection,
dependency loading, missing and corrupt modules, and reuse with host callbacks
that fail if called.
