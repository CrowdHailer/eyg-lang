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

### Dependent-review refinement

Migrating the hub cache showed that the old `list_references` contract silently omitted references without CIDs. That name is misleading with the explicit model. It now returns every `Reference`; `list_content_references` is the explicit projection for content and pinned module CIDs. This keeps dependency discovery exhaustive while making CID-only consumers state their restriction.

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

## `eyg_hub`

### Assessment

The explicit types materially simplify the cache. `FetchStatus.DependsOn` now stores `ir.Reference` directly instead of a partial duplicate `Dependency`, and the hub's duplicate release type has been removed in favor of `ir.Release`. Resolution is one exhaustive match over `Content`, `Package`, `Version`, `Pinned`, and `Relative`; no version or CID sentinel checks remain.

The review also exposed an ordering requirement for latest-package resolution. A pull batch must register every release before resuming `Package` dependencies, otherwise an early release in the batch could be mistaken for the latest one. The cache now resolves named dependencies only after registration and records the highest fetched version.

### Changes and tests

- Pointed `eyg_ir`, `eyg_analysis`, and `eyg_interpreter` at local packages.
- Reused `ir.Reference` for suspended dependencies and `ir.Release` for release APIs.
- Made preparation and runtime resolution exhaustive across all reference forms; relative references are deliberately unavailable in a hub cache and produce no network action.
- Added focused tests for reference lookup, package/version evaluation, missing-package pulls, relative rejection, preparation actions, and latest selection across one pull batch.
- Passed 31 tests on both Erlang and JavaScript/Bun with warnings treated as errors.

## `morph`

### Assessment

The explicit model greatly improves the editable tree. Morph previously duplicated only three IR constructors and therefore could not represent latest-package and version-only references without sentinels. Its editable expression now stores `ir.Reference` directly, making IR conversion lossless and reducing three conversion branches to one in each direction.

UI-specific transformations remain narrow: content-CID and pinned-release pickers match only the forms they can edit, while `insert_explicit_reference` supports all forms. This separation is clearer than allowing a picker to construct partially meaningful triples.

### Changes and tests

- Pointed `eyg_ir`, `eyg_analysis`, and `eyg_interpreter` at local packages.
- Reused `ir.Reference` and `ir.Release` in editable and analysis models.
- Updated navigation, rendering, actions, transformations, and current analysis calls.
- Added five-form round-trip, navigation, and transformation coverage using a non-vacant CID.
- Passed 29 tests on both configured/default and explicit JavaScript/Bun runs with warnings treated as errors.

## `touch_grass`

### Assessment

The reflected EYG AST mapping is clearer and now exhaustive. Each `ir.Reference` variant maps directly to its public AST tag, so package-only and version-only forms are no longer collapsed into `ReleaseReference` records containing fake values. The outer `Reference` wrapper remains an implementation detail; EYG consumers receive the five useful semantic forms.

### Changes and tests

- Pointed `eyg_ir`, `eyg_analysis`, and `eyg_interpreter` at local packages.
- Added direct encodings for `ContentReference`, `PackageReference`, `VersionReference`, `ReleaseReference`, and `RelativeReference`.
- Added one focused encoding test per form using a real non-vacant CID.
- Passed 24 tests on both Erlang and JavaScript/Bun with warnings treated as errors.

## EYG `json`

### Assessment

The explicit reference wire format needs to distinguish `@package`, `@package:version`, and a pinned release by field presence. Adding a general `optional_field` decoder is preferable to reintroducing sentinels or creating reference-specific JSON parsing logic.

### Changes and tests

- Added `json.decode.optional_field`, returning `Some(value)` when present and `None({})` when absent.
- Added tests for present and absent fields.

## EYG `eyg` AST

### Assessment

The EYG-side AST now has the same five semantic forms as Gleam and the reflected type. Optional DAG-JSON fields are interpreted once at the decode boundary; the rest of the package works with explicit `PackageReference`, `VersionReference`, and `ReleaseReference` values. This is clearer and rejects the malformed CID-without-version combination rather than assigning hidden defaults.

### Changes and tests

- Decoded the three `@` encodings by field presence.
- Encoded package-only and version-only AST values without placeholder fields.
- Added package, version, and relative round-trip tests while retaining the pinned release fixture/CID test.

## `gleam_compiler`

### Assessment

The explicit model makes the compiler's current limitation clearer. JavaScript generation cannot link module values, so every reference form is now rejected through an exhaustive `ir.Reference` match with one stable diagnostic instead of falling into a generic expression wildcard. A future reference variant will force this behavior to be reviewed at compile time.

The `to_js` API still accepts CID-to-type information for analysis but no corresponding linked values for code generation. That pre-existing mismatch remains outside this reference representation migration.

### Changes and tests

- Pointed `eyg_ir`, `eyg_analysis`, and `eyg_parser` at local packages.
- Migrated effect inference to the current analysis context/check API.
- Added exact panic-message coverage for content, package, version, pinned, and relative references.
- Passed 13 JavaScript/Bun tests with warnings treated as errors.

## `gleam_cli`

### Assessment

The CLI is the clearest demonstration that the core change is worthwhile. Its old release lookup decoded three meanings from `version == 0` and `module == vacant_cid`; it now dispatches directly on `Content`, `Package`, `Version`, `Pinned`, and `Relative`. The interpreter's single explicit-reference break also reduces three duplicated loop branches to one.

Reference-to-CID resolution remains centralized in `eyg_hub.cache.reference`; the CLI delegates to it rather than repeating package rules. A pin to the vacant module CID is consequently a real pinned release and cannot be mistaken for an unpinned package/version request.

### Changes and tests

- Pointed all seven direct migration-stack dependencies at local packages.
- Replaced old constructors, release DTOs, break variants, and sentinel dispatch throughout execution, IR helpers, and source origins.
- Preserved relative import resolution by matching `Relative(location)` explicitly.
- Added focused resolution and source-origin tests, including the vacant-CID pin regression; no snapshots changed.
- Passed 70 JavaScript/Bun tests with warnings treated as errors.

## `pal`

### Assessment

Pal does not inspect IR references directly, so the core type change neither improves nor harms its source clarity. Its value in this migration is integration coverage: local dependency wiring proves that the upgraded hub, analysis, interpreter, Morph, touch_grass, and IR APIs compose without a vendored compatibility copy.

### Changes and tests

- Pointed `eyg_ir`, `eyg_analysis`, `eyg_interpreter`, and `touch_grass` at local packages; other local stack packages remain path dependencies.
- No source or behavioral changes were needed.
- Passed its JavaScript/Bun test with warnings treated as errors.
