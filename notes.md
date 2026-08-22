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

## `eyg_parser`

### Assessment

The explicit variants substantially improve parser clarity. Each syntax form now maps directly to one constructor, so parsing no longer imports DAG-JSON solely to manufacture placeholder values. The parser also rejects version `0`, matching the documented positive-integer syntax and preventing the old sentinel from re-entering the IR as an ordinary version.

### Changes and tests

- Pointed `eyg_ir` at the local package so this migration is tested against the new API.
- Mapped content, latest package, exact version, pinned release, and relative import syntax to their matching variants.
- Updated parser expectations and added a version-zero rejection case.

## `eyg_analysis`

### Assessment

The core reference change improves analysis diagnostics and removes a misleading code path. Previously relative references were reported as an undefined release with their path stored as a package, version `0`, and `vacant_cid`; package and version-only references were likewise indistinguishable from pinned releases. Analysis now reports `UndefinedPackage`, `UndefinedVersion`, `UndefinedRelease(Release)`, and `UndefinedRelative` directly.

The existing CID dictionary can resolve only content and pinned references. Keeping that limitation explicit is clearer than pretending it resolves all forms. The later `fetch-refs` work should replace this dictionary boundary with a resolver that receives the exact `Reference` variant.

### Changes and tests

- Pointed both `eyg_ir` and `eyg_parser` at their local packages.
- Preserved the original reference variant in the analyzed tree instead of rewriting successful and failed lookups to content references.
- Expanded the reflected AST type with package-only and version-only tags.
- Added coverage for all five reference diagnostics and successful concrete-CID lookup.

## `eyg_interpreter`

### Assessment

The explicit reference model simplifies interpreter suspension. Three runtime break variants are replaced by `UndefinedReference(ir.Reference)`, preserving the exact unresolved request without duplicating reference structure in the interpreter. Rendering still gives form-specific messages and hints by matching the nested variant.

### Changes and tests

- Pointed `eyg_ir` at the local package.
- Suspended every reference expression with its complete `Reference` value.
- Added execution coverage for all five variants.
