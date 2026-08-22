# Explicit references migration

## Goal

Replace overloaded release triples with explicit IR variants and migrate every local `eyg_ir` consumer. The old representation used version `0` for latest-package references and `dag_json.vacant_cid` for references without a pinned module. Those values were ambiguous because the vacant module has a valid CID and version validity was enforced outside the type.

## `eyg_ir`

### Assessment

The core change improves clarity. `Content`, `Package`, `Version`, `Pinned`, and `Relative` state which resolution information is present, while `Release` gives pinned package data one shared type. Callers no longer need to remember combinations of sentinel values.

The initial layout commit was incomplete: helpers, traversal, and DAG-JSON still referred to the removed constructors. Completing those APIs confirms that the variants simplify the implementation. `list_references` now visibly collects concrete CIDs only, `list_named_references` returns `List(Release)`, and `map_release` maps a `Release` rather than three positional values.

### Serialization decision

The existing DAG-JSON `"@"` node is retained with fields based on the information present:

| Reference | Fields |
| --- | --- |
| `Package(package)` | `0`, `p` |
| `Version(package, version)` | `0`, `p`, `r` |
| `Pinned(Release(package, version, module))` | `0`, `p`, `r`, `l` |

Existing pinned releases retain their encoding and content identifiers. Content and relative encodings are unchanged. A module CID without a version is rejected. Old sentinel triples decode as pinned releases rather than being interpreted through hidden values; this is the only unambiguous reading of their serialized fields.

### API and tests

- Added helpers for all five variants: `reference`, `package`, `version`, `release`, and `relative`.
- Updated traversal and rewriting for the wrapper `Reference` expression.
- Added tests for helper construction, concrete/reference collection, typed release mapping, all reference round trips, and invalid package encodings.
- Bumped `eyg_ir` to `3.0.0` because replacing public expression constructors is a breaking API change.
