# TypeSafe AI

Follow the advice in [../api_clients.md](../api_clients.md), with the deliberate
public API choice below.

The OpenAPI specs are available at:
- https://docs.typesafe.ai/api/system-one.md
- https://docs.typesafe.ai/api/list-models.md

Use the Gleam implementation in
[`../../packages/intelligence/src/intelligence/jev.gleam`](../../packages/intelligence/src/intelligence/jev.gleam)
as the model for the **public library API**, not just the HTTP protocol.
