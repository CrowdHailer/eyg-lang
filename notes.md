---
name: Bundle branch review
description: Correctness errors found while reviewing CAR upload and sharing modules by hash.
date: 2026-09-05
---

# Bundle branch review

## Confirmed errors

- Fixed: Transitive relative-import cycles were not tracked while building a share bundle, so a graph such as `root -> A -> B -> A` recursed indefinitely.
- Pending: Modules fetched by content identifier are accepted without checking that the returned module has the requested hash.
- Pending: The share client accepts a response CID that differs from its local root and reduces useful HTTP failures to `bad module lookup`.
- Pending: Hub module lookup validates a parsed CID but queries with the original, potentially noncanonical URL text.
- Pending: The CAR endpoint rejects valid archives whose root is not the first block or which contain unreachable blocks instead of shaking them to the graph reachable from the declared root.
- Pending: Pinned references are accepted by module CID without validating their package and version against the release ledger.
- Pending: Stored dependency source is trusted under its database CID and recursive stored dependency validation has no cycle guard.
