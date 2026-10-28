---
name: JSON boundaries for embedded EYG
description: Exchange plain data and declare closed effect types for a host.
---

# JSON boundaries for embedded EYG

`eyg/embed/json` converts host data and describes effect signatures without
exposing interpreter internals. It is part of
[gleam_embed](../packages/gleam_embed/); see the [host loop](./embedding_in_gleam.md).

| EYG value | JSON |
| --- | --- |
| Integer, String | number, string |
| True({}), False({}) | true, false |
| List, Record | array, object |
| Ok(42) | {"$":"Ok","value":42} |
| None({}) | {"$":"None"} or {"$":"None","value":{}} |

`value_decoder()` decodes this format; `to_json(value)` encodes it.
The `$` record key is reserved for tags. Malformed tags and extra tag fields
are errors. Null, fractional numbers, binaries and functions are unsupported.
Integers outside the JavaScript safe range, ±(2^53−1), are rejected.
Use strings or lists when the host needs an explicit byte representation.

Types use these closed descriptions:

```json
{
  "integer": "integer",
  "strings": {"list": "string"},
  "record": {"record": {"id": "integer", "done": "boolean"}},
  "union": {"union": {"Ready": "unit", "Failed": "string"}},
  "result": {"result": {"ok": "unit", "error": "string"}}
}
```

Each value above is a separate type descriptor for `type_decoder()`.
`effects_decoder()` accepts a map of labels to request and reply types:

```json
{"Add":{"lift":"integer","lower":"integer"}}
```

Decode each host reply with `value_decoder()`, then call
`conforms(value, declared_lower_type)` before resuming the program.
It checks nested payloads, allowed union variants and exact record fields;
decoding by itself does not check the effect's declared type.

From packages/gleam_embed, `gleam test --runtime node` checks round trips,
malformed descriptors, tag collisions and wrong nested replies. The same
checks run on Bun. No additional EYG effects are introduced by this boundary.
