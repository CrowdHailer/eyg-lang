# Recommended tree and graph walks

## Status

Proposed.

This plan describes reusable traversal operations for the EYG intermediate
representation, the package that should own each operation, and the existing
code that should be migrated to those operations.

The accompanying [tutorial](./tutorial.md) explains the programming techniques
used here without assuming prior knowledge of functional programming,
catamorphisms, monads, or recursion schemes.

## Goals

- Define the structure of an EYG IR tree in one place.
- Remove repeated `Lambda`, `Apply`, and `Let` recursion from the repository.
- Make traversal order, failure, state, scope, and replacement behavior explicit.
- Support reference pinning and recursive type checking without putting IO in
  the IR or analysis packages.
- Share module validation policy between the CLI, browser-compatible code, and
  server.
- Detect graph cycles, missing modules, and incorrect pins deterministically.
- Make Morph paths, navigation, rendering, and analysis use one editable-tree
  topology.
- Preserve current public behavior unless a task explicitly identifies a bug
  that should be corrected.

## Non-goals

- Do not build a general-purpose recursion-schemes framework for Gleam.
- Do not make `gleam_ir` depend on filesystems, HTTP, databases, promises,
  type inference, or runtime evaluation.
- Do not replace the interpreter's continuation machine with a whole-tree walk.
- Do not force compiler, type inference, or editor semantics into generic IR
  traversal callbacks.
- Do not use a generic abstraction where a direct function remains clearer.

## Terminology

- **Structural child**: an IR node stored directly by another IR constructor.
  `Lambda` has one, while `Apply` and `Let` have two.
- **Tree walk**: visits structural children of one source tree.
- **Reference edge**: connects a reference leaf to separately loaded module
  source. Following reference edges forms a graph, not an IR tree.
- **Fold**: replaces a tree with a summary value.
- **Rewrite**: rebuilds a tree, possibly replacing some nodes.
- **Accumulator**: state returned by one visit and supplied to the next visit.
- **Inherited context**: data passed from a parent to a child and restored when
  returning, such as variable scope.
- **Traversal order**: the order in which nodes and children are visited.
- **Recursion callback**: a function supplied to a handler that starts the same
  traversal on another node. It is not a continuation.
- **Open recursion**: recursive calls are supplied explicitly rather than being
  completely fixed inside the recursive function.
- **Topology**: constructor and child-position structure, ignoring metadata and
  optionally ignoring leaf payloads.
- **Spine**: a repeated low-level encoding, such as nested `Apply` nodes forming
  one multi-argument call.

## Linked resources

### State monad tree example

[Control.Monad.State.Strict: `numberTree`](https://hackage.haskell.org/package/mtl-2.3.2/docs/Control-Monad-State-Strict.html#g:4)
is the best concrete introduction to state-threading recursion. It transforms a
tree while carrying a table of values already seen. The state returned after
processing the current node is passed into the left subtree, and the state
returned by the left subtree is passed into the right subtree.

This corresponds to EYG passing an updated counter, cache, reference type
environment, or compiler name supply between recursive calls.

It does not cover failure, node replacement, external module loading, or a
caller-controlled recursion callback. Haskell's word "Strict" describes
evaluation of state, not stricter traversal rules.

### Monadic map-accumulate

[`Data.Traversable.mapAccumM`](https://hackage.haskell.org/package/base-4.22.0.0/docs/Data-Traversable.html#v:mapAccumM)
is the canonical high-level description of a traversal that rebuilds a
same-shaped structure, threads an accumulator, and performs an action in a
chosen effect. That effect can support failure when `m` is `Either`/`Result`:

```haskell
mapAccumM
  :: (Monad m, Traversable t)
  => (s -> a -> m (s, b))
  -> s
  -> t a
  -> m (s, t b)
```

The EYG
[reference-walk test prototype](../packages/gleam_cli/test/eyg/cli/internal/reference_walk_test.gleam)
has the explicit Gleam shape:

```gleam
fn(node, state) -> Result(#(node, state), error)
```

`state` corresponds to `s`, `Result` corresponds to one choice of `m`, and the
returned node is the rebuilt structure. Haskell returns `(state, value)`, while
the EYG prototype returns `#(value, state)`. EYG cannot use this Haskell API
directly: Gleam does not encode higher-kinded `Traversable` instances, and EYG
may follow reference edges to modules that are not structural children of the
original tree. A general EYG rewrite can also change topology, while
`Traversable` preserves the container's shape.

### Mendler-style recursion callback

[`recursion-schemes.mcata`](https://hackage.haskell.org/package/recursion-schemes-5.2.3/docs/Data-Functor-Foldable.html#v:mcata)
is the closest formal example of a handler receiving the recursive operation:

```haskell
mcata :: (forall y. (y -> c) -> f y -> c) -> Fix f -> c
```

An ordinary fold receives already-computed child results. `mcata` instead gives
the handler a function it can use to recurse. This resembles the reference
handler in the prototype: hashing can load another module and recursively pin
it, while checking can recursively prepare a dependency before inferring its
type.

The EYG walk is not literally `mcata`. Its callback can recurse into newly
loaded source outside the original tree, carries explicit state and errors, and
does not gain the termination guarantees of the Mendler encoding.

### Open recursion

[Ralf Hinze, Closed and Open Recursion](https://www.cs.ox.ac.uk/ralf.hinze/talks/Open.pdf)
provides the vocabulary for making the recursive operation an explicit input.
The EYG prototype uses selective open recursion: the main walk owns normal IR
children, but its reference policy can invoke the recursive operation on loaded
source.

The more precise name for that input is **recursion callback** or **recursive
capability**. A continuation represents the remainder of the current
computation, which is not what this callback does.

The prototype demonstrates the callback shape, not the complete production
policy. Its strict mode rejects unpinned releases but still accepts relative
references, and it does not yet memoize modules or detect graph cycles. Those
requirements belong to the graph preparation phases below.

## Architectural decision

The structural definition of an IR node belongs in `gleam_ir`. Semantic
policies stay in the packages that understand them.

| Package | Responsibilities |
| --- | --- |
| `eyg_ir` (`packages/gleam_ir`) | Child structure, pure folds and rewrites, stateful/fallible tree walks, syntactic scope, references as syntax, topology zip, encoded-spine views |
| `eyg_analysis` (`packages/gleam_analysis`) | Type/effect inference, type-tree traversal, reference type requests, inference errors |
| `topological` | Generic graph ordering, cycle detection, dependency-first walks |
| `eyg_hub` (`packages/gleam_hub`) | Sans-IO module graph preparation and validation policy |
| `eyg_cli` (`packages/gleam_cli`) | Filesystem-relative resolution, HTTP lookup, hashing, command orchestration, diagnostics |
| `hub` | PostgreSQL resolver, HTTP responses, persistence after validation |
| `eyg_compiler` (`packages/gleam_compiler`) | Compiler-specific rewrites and stateful passes |
| `eyg_interpreter` (`packages/gleam_interpreter`) | Evaluation machine; consume shared free-variable queries and canonical builders where appropriate |
| `eyg_parser` (`packages/gleam_parser`) | Text parsing; consume canonical Let-spine operations where they remove duplicate structural peeling |
| `morph` | Editable-tree traversal, paths, zippers, editor transformations |
| `website` | UI adapters and rendering policies |
| `touch_grass` | EYG effect wire representation, consuming generic IR folds where useful |
| EYG package `eyg` (`eyg_packages/eyg`) | Flat prefix-AST consumption and DAG-JSON rendering, synchronized through protocol fixtures |

The first low-level implementation should live beside `Node` and `Expression`
in `packages/gleam_ir/src/eyg/ir/tree.gleam`. A child module such as
`eyg/ir/tree/traverse` would need to import `eyg/ir/tree`; existing published
helpers in `tree.gleam` could not then delegate back to it without an import
cycle. A separate traversal module is viable only after moving the data
declarations to a lower-level module and defining a public compatibility plan.


## Phase 1: foundational IR traversal

### Bottom-up fold

- [ ] Implement `fold_bottom_up`, whose algebra receives already-folded child
      results.

### Rewrite and fallible rewrite

- [ ] Add `rewrite_until_stable` only for a demonstrated caller, with explicit
      nontermination safeguards or a caller-provided limit.

### Stateful traversal and rewrite

- [ ] Implement `map_accum_pre_order` for parent-first numbering and collection.
- [ ] Implement `try_map_accum_pre_order` with explicit state threading.
- [ ] Implement `rewrite_accum_bottom_up` only for callers whose rules must see
      rewritten children.
- [ ] Implement the required fallible variant returning
      `Result(#(Node(meta), state), error)`.
- [ ] Put pre-order or bottom-up behavior in the function name rather than
      relying on callback documentation alone.
- [ ] Decide whether state produced before an error is intentionally discarded.
- [ ] Keep inherited context separate from sibling-threaded state.
- [ ] Test deterministic state order on `Apply` and `Let`.
- [ ] Test shared state across siblings and nested nodes.
- [ ] Test first failure and confirm whether partial state is observable.

Gleam does not need a `StateT` abstraction for this. Explicit tuples and
`Result` make the behavior readable and keep the API concrete.

## Phase 2: IR-specific traversals

### Reference sites

- [ ] Define one reference sum type covering content, release, and relative
      references.
- [ ] Preserve metadata for every occurrence.
- [ ] Implement `fold_references` without deduplication.
- [ ] Implement `rewrite_references` and `try_rewrite_references`.
- [ ] Keep ordered-unique collection as compatibility wrappers rather than the
      primitive behavior.
- [ ] Represent pinned and unpinned releases without treating `vacant_cid` as a
      valid content dependency.
- [ ] Test duplicate sites with distinct metadata and all reference forms.
- [ ] Test reference rewrites in function, argument, definition, and body.

### Structural topology zip

- [ ] Implement a lockstep walk over two IR trees.
- [ ] Return a descriptive mismatch rather than asserting or truncating.
- [ ] Report the path and both mismatched constructors.
- [ ] Provide a child-topology mode that requires recursive arity and position
      agreement while allowing different leaf constructors.
- [ ] Provide a constructor-topology mode for callers that require constructor
      identity while ignoring payloads.
- [ ] Define a separate exact-syntax comparison rather than overloading topology
      zip with payload equality.
- [ ] Require recursive constructor and child-position agreement.
- [ ] Permit metadata types to differ.
- [ ] Use child-topology mode for analysis pairing until inference preserves
      original release and relative reference constructors.
- [ ] Test equal node counts with different topology.
- [ ] Test mismatches at root, middle, and deepest leaf.
- [ ] Add a metadata-pairing specialization for analysis consumers.

### Canonical encoded-spine views

- [ ] Add an application view: function and ordered arguments.
- [ ] Add a Lambda view: ordered parameters and body.
- [ ] Add a Let/block view: ordered assignments and tail.
- [ ] Add a list view: ordered items and proper/improper tail.
- [ ] Add a record view: ordered fields, `Extend`/`Overwrite`, and tail/original.
- [ ] Add a case view: ordered branches and optional otherwise.
- [ ] Return `Option` or `Result` for malformed and partially applied encodings.
- [ ] Test builder/view round trips, empty spines, improper lists, record
      overwrite, and open cases.
- [ ] Define metadata ownership for synthesized intermediate nodes.

## Phase 3: refactor `gleam_ir`

### DAG-JSON encoding

Target: `eyg/ir/dag_json.to_data_model`.

- [ ] Evaluate expressing the encoder as a post-order fold.
- [ ] Keep wire tags, keys, bytes, and CIDs byte-for-byte stable.
- [ ] Centralize constructor/tag information where decoder and encoder can share
      it without obscuring either implementation.
- [ ] Run exact block/CID fixtures, not only semantic JSON comparisons.
- [ ] Do not migrate if the fold makes the stable codec harder to audit.

### Block and snippet helpers

Targets: `tree.from_block`, `tree.do_gather_snippets`, and
`tree.gather_snippets`.

- [ ] Reimplement repeated Let peeling with the canonical Let-spine view.
- [ ] Before migration, test and document whether `tree.from_block` accepts
      source-order or already-reversed assignments; its current `list.fold`
      reverses source-order input.
- [ ] Preserve or intentionally version `gather_snippets`' documented reversed
      assignment result.
- [ ] Remove library printing from unexpected-tail handling and return an
      explicit result or remainder.
- [ ] Preserve comment/snippet grouping independently of the selected assignment
      order contract.

## Phase 4: type traversal and inference

### Type-tree traversal

Owner: `gleam_analysis`.

- [ ] Define type-specific one-layer children and `map_children` for
      `isomorphic.Type`.
- [ ] Document `Fun`: argument, effect, return.
- [ ] Document row and effect extension child order.
- [ ] Reimplement structural branches of `binding.resolve` through it.
- [ ] Reimplement structural branches of `binding.gen` through it.
- [ ] Reimplement `contextual.ftv` through a type fold.
- [ ] Reimplement occurs checking/level lowering through a fallible fold or
      explicit worklist using canonical type children.
- [ ] Reimplement `binding.instantiate` with stateful type mapping.
- [ ] Preserve deterministic allocation of fresh type variables.
- [ ] Add tests for every type constructor, deep rows/effects, bound-variable
      chains, repeated quantified variables, and recursive occurrence.

### Reference-aware inference protocol

- [ ] Stop identifying every reference only by CID.
- [ ] Define full syntactic reference sites in `eyg_ir`.
- [ ] Let relative lookup receive site metadata or a caller-supplied generic
      origin key; do not make `eyg_analysis` depend on CLI/filesystem origin
      types.
- [ ] Keep inference pure and synchronous.
- [ ] Let prepared contexts supply a lookup function or table returning a
      resolved polymorphic type and optional canonical CID, or a
      reference-specific error.
- [ ] Keep `with_references(Dict(Cid, Poly))` as a content-only compatibility
      adapter if external callers require it.
- [ ] Preserve the original reference constructor in the analyzed tree.
- [ ] Remove the current relative-reference use of one shared `vacant_cid` key.
- [ ] Validate package/version/CID identity before inference rather than looking
      up releases only by CID.
- [ ] Test two relative paths, the same path under two origins, two unpinned
      releases, incorrect pins, and preserved reference metadata.

### Analysis topology pairing

Targets: `contextual.all_errors` and `contextual.info_at`.

- [ ] Replace flatten-two-trees plus `strict_zip` with structural topology zip.
- [ ] Make topology mismatch an explicit internal analysis error.
- [ ] Let `info_at` short-circuit without allocating two complete metadata lists.
- [ ] Test equal-length/different-shape trees and every metadata position.

### Update inference consumers

- [ ] Update `gleam_hub` cache type environments.
- [ ] Update `eyg_compiler.compiler.infer_effects`; it directly calls `j.infer`
      with the old CID-only dictionary.
- [ ] Update CLI shell type queries.
- [ ] Update Morph analysis contexts.
- [ ] Update `touch_grass` browser harness inference contexts.
- [ ] Update website reload and workspace contexts.
- [ ] Reduce direct calls to `infer.infer` and `infer.do_infer` in favor of the
      public context API.
- [ ] Preserve browser-compatible synchronous inference and existing effect
      contexts.

## Phase 5: module dependency graph

Tree traversal finds reference sites within one module. Module preparation must
then follow those sites as a graph.

### Generic graph operations

Owner: `topological`.

- [ ] Add a resolver-driven graph walk that need not receive a fully materialized
      graph.
- [ ] Track temporary/`Visiting` and permanent/`Done` states.
- [ ] Return the complete closed cycle path.
- [ ] Visit shared subgraphs once.
- [ ] Support deterministic dependency-first order.
- [ ] Preserve child order supplied by the resolver.
- [ ] Use dictionaries/sets rather than repeated list scans for `O(V + E)`
      behavior where practical.
- [ ] Keep existing `sort` output stable or add a new API.
- [ ] Test diamonds, multiple roots, deep graphs, missing nodes, resolver errors,
      and cycles entered through shared subgraphs.

### Sans-IO module preparation

Owner: `gleam_hub`.

- [ ] Define graph state such as `Unseen`, `Visiting`, and
      `Prepared(type, pinned_source)`.
- [ ] Inject module/release lookup rather than importing filesystem, HTTP, or DB
      code.
- [ ] Consider a request/response step protocol instead of a callback if hidden
      IO or asynchronous adapters become difficult to control.
- [ ] Resolve dependencies before hashing or inferring their parent.
- [ ] Cache prepared results by canonical identity.
- [ ] Detect cycles before recursive re-entry.
- [ ] Verify loaded content hashes to every declared pinned CID.
- [ ] Distinguish missing, invalid, incorrectly pinned, and transient lookup
      errors.
- [ ] Return the prepared dependency closure in dependency-first order for
      upload and diagnostics.
- [ ] Keep source origins available for relative path resolution.
- [ ] Test direct, transitive, diamond, duplicate, missing, incorrect-pin, and
      cyclic dependency graphs.
- [ ] Test latest-release normalization, `version == 0` with a CID, and explicit
      version with a vacant CID.

### Preparation policies

- [ ] Define a permissive local policy that resolves relative and unpinned
      references and returns pinned source.
- [ ] Require release lookup to return the selected concrete version and CID.
- [ ] Rewrite `ReleaseReference(package, 0, vacant_cid)` to
      `ReleaseReference(package, selected_version, selected_cid)`; adding only a
      CID does not remove the mutable latest-version selector.
- [ ] Define a strict hosted-module policy that rejects relative references and
      unpinned releases.
- [ ] Make strict policy reject `version == 0` regardless of whether a CID was
      supplied, and reject malformed release selector/pin combinations.
- [ ] Make both policies share graph traversal, CID verification, dependency
      inference, and errors.
- [ ] Never let the strict server policy resolve "latest" while validating
      immutable shared content.
- [ ] Make policy differences visible in tests rather than separate recursive
      implementations.

### Refactor `gleam_hub` cache

Targets: `eyg/hub/cache.prepare`, `pull_if_any_missing`, `with_module`,
`pulled`, `loop`, `static_loop`, `blocked_by`, `handle_return`, and `cascade`.

- [ ] Replace separate content/release scans with one reference-site pass.
- [ ] Do not fetch `vacant_cid` for an unpinned release.
- [ ] Maintain explicit dependencies and reverse dependents.
- [ ] Replace repeated scans of fetching modules where the graph index can answer
      readiness directly.
- [ ] Factor duplicated content/release lookup in dynamic and static loops.
- [ ] Retain interpreter continuations as graph payload, not as a dependency of
      `topological`.
- [ ] Preserve dynamic dependency discovery during interpretation.
- [ ] Ensure cascaded failure reaches every dependent once.
- [ ] Add content/release cycles, diamond completion, shared failure, mismatched
      release, and deterministic completion tests.

## Phase 6: CLI and server integration

### CLI resolver adapter

Owner: `gleam_cli`.

- [ ] Implement origin-aware relative path resolution.
- [ ] Implement content and release lookup through the existing client/cache.
- [ ] Supply SHA-256 to the pure CID operation.
- [ ] Translate preparation errors into source-aware CLI diagnostics.
- [ ] Preserve dependency source origins across recursive loads.
- [ ] Ensure two modules importing the same relative spelling from different
      directories resolve independently.
- [ ] Reject relative references from origins without a source directory,
      including inline, stdin/pipe, and REPL input, with a source-aware error.
- [ ] Define published content/release-origin behavior explicitly; immutable
      hosted modules should not gain filesystem-relative meaning.
- [ ] Add relative-reference tests for file, inline, stdin, REPL, content, and
      release origins.

### CLI commands

Targets: current commands `eyg/cli/check`, `compile`, `share`, and `publish`,
plus the planned module-hash command on branch `bot/cli-hash`. The hash command
does not yet exist on this branch, so pinning and source-CID calculation must
first be an internal preparation operation usable by share and publish.

- [ ] Make `check` prepare references and infer dependencies before the root.
- [ ] Make `compile` receive a prepared reference type environment instead of an
      empty dictionary.
- [ ] Make preparation compute the CID of rewritten pinned source.
- [ ] Make `share` upload missing dependencies before dependents and upload the
      rewritten pinned root.
- [ ] Make `publish` publish the CID of that pinned root.
- [ ] Integrate the user-facing hash command after the shared preparation API is
      available, rather than retaining its own graph recursion.
- [ ] Decide whether `check` and `compile` print selected release versions when
      resolving unpinned releases.
- [ ] Reject unresolved references at reproducibility boundaries.
- [ ] Promote the reference-walk prototype tests to production unit and command
      tests.
- [ ] Add nested relative, named, and content reference fixtures.
- [ ] Add cycle, missing dependency, incorrect CID, and referenced-function
      compile tests.

### Hub server adapter

Owner: `hub` using `gleam_hub` policy.

- [ ] Load referenced modules from PostgreSQL through an injected resolver.
- [ ] Apply the strict hosted-module policy before persistence.
- [ ] Reject relative and unpinned release references.
- [ ] Infer transitive dependency types before checking the submitted module.
- [ ] Verify every stored source against its requested CID.
- [ ] Combine soundness and purity preparation so dependency traversal is not
      repeated unnecessarily.
- [ ] Map missing, cycle, incorrect-pin, type, and purity failures to stable HTTP
      responses.
- [ ] Keep request-size checks and persistence behavior unchanged.
- [ ] Add controller tests for valid pinned, transitive, missing, mismatched,
      cyclic, relative, and unpinned dependencies.

## Phase 7: compiler refactorings

Keep compiler rules in `gleam_compiler`; use IR traversal only for structural
plumbing.

### Monadic lowering

Target: `eyg/compiler.monadic`.

- [ ] Express child recursion as a bottom-up rewrite.
- [ ] Keep the effect-aware `Let` rule compiler-specific.
- [ ] Do not re-enter generated `bind` applications.
- [ ] Preserve metadata on generated nodes.
- [ ] Test pure/effectful and nested Lets with no double lowering.

### Let unnesting

Target: `eyg/compiler/ir.unnest`.

- [ ] Use a bottom-up rewrite for local hoisting rules.
- [ ] Preserve function-before-argument evaluation order.
- [ ] Make repeated normalization explicit rather than hidden in generic
      `rewrite`.
- [ ] Test both application children, nested definitions, shadowing, and final
      idempotence.

### Continuation normalization

Target: `eyg/compiler/ir.k`.

- [ ] Use inherited safety context plus a state-threaded fresh-name counter.
- [ ] Preserve current reset rules for Lambda and Let children.
- [ ] Preserve exact `$kN` allocation order unless intentionally versioned.
- [ ] Add nested application and semantic evaluation-order tests.

### Alpha renaming

Target: `eyg/compiler/ir.alpha`.

- [ ] Use a scope-aware stateful rewrite.
- [ ] Keep a stack/environment from source names to generated names.
- [ ] Walk Let definitions in the old environment and bodies in the extended
      environment.
- [ ] Leave free variables unchanged.
- [ ] Preserve deterministic generated-name order.
- [ ] Add nested shadowing and outer-name-in-definition tests.

### Encoded-spine rendering

Targets: `eyg/compiler/js.assign_to`, `do_render`, `render_body`,
`gather_items`, `gather_extends`, `gather_overwrites`, and `render_branches`.

- [ ] Replace local Let, list, record, overwrite, case, and application peeling
      with canonical `eyg_ir` spine views.
- [ ] Preserve function-before-argument evaluation and generated
      field/item/branch order.
- [ ] Preserve special handling of `bind`.
- [ ] Return an explicit unsupported/malformed result instead of panicking on an
      improper record.
- [ ] Test improper lists, malformed record spines, open cases, partially
      applied primitives, and existing exact JavaScript snapshots.

## Phase 8: interpreter and Morph refactorings

### Interpreter and CLI encoded-spine construction

Targets: `eyg/interpreter/capture.do_capture`, `capture_defunc`, and
`eyg/cli/script.wrap_list`.

- [ ] Use metadata-aware canonical list, record, application, and Let builders
      instead of manually nesting `Apply` nodes.
- [ ] Keep capture environment accumulation and deduplication separate from
      structural construction.
- [ ] Preserve item, field, applied-argument, and script-argument order and the
      supplied metadata.
- [ ] Extend capture round-trip tests with nested lists/records and test script
      argument order.

Do not migrate the interpreter's evaluation machine to a tree fold. Its
evaluation order, effects, references, and suspension semantics are a different
abstraction.

### Editable one-layer topology

Owner: `morph`.

- [ ] Define editable expression children separately from editable pattern and
      label sites.
- [ ] Document canonical order for blocks, calls, functions, lists, records,
      selections, and cases.
- [ ] Implement editable `map_children`, `fold`, `rewrite`, and fallible forms
      only where callers justify them.
- [ ] Reimplement `editable.open_all` as a rewrite.
- [ ] Test every Editable constructor and identity behavior.

### Morph destructuring

Target: `morph/editable.is_free`.

- [ ] Replace local recursion with `eyg_ir`'s corrected free-variable query.
- [ ] Preserve the rule that selector Lets cannot be collapsed while the
      original parameter remains free.
- [ ] Add Lambda/Let shadowing and residual-use tests.

### Morph paths and zipper navigation

Targets: `morph/projection.path_to_zoom`, `path`, `focus_at`,
`do_focus_at`, and navigation's first/last/next/previous/vacant functions.

- [ ] Define one ordered `EditableSite` topology including expressions,
      patterns, labels, fields, branches, and optional tails.
- [ ] Derive path lookup, first/last, next/previous, and vacant search from it.
- [ ] Keep `Projection` as the rebuilding zipper representation.
- [ ] Make empty calls/functions/lists/records/cases total rather than asserting.
- [ ] Normalize reversal conventions in zipper pre/post lists internally.
- [ ] Add path/focus/rebuild round-trip properties.
- [ ] Add forward/reverse traversal properties.
- [ ] Add empty collection and wraparound tests.

### Canonical Morph path metadata

Targets: `editable.to_annotated`, projection path conversion, and Lustre
rendering path attributes.

- [ ] Generate canonical path segments from the editable site topology.
- [ ] Use those paths for IR metadata, focus, rendering, and error lookup.
- [ ] Resolve the current conflicting record-overwrite tail formulas.
- [ ] Test records with at least two fields, case labels/bodies, destructured
      parameters, and every rendered path.
- [ ] Verify each rendered path resolves through `focus_at`.

### IR and Editable spine conversion

Targets: Morph's `from_annotated`, `gather_parameters`, `gather_destructure`,
`do_gather_destructure`, `gather_cons`, `gather_extends`, `gather_overwrite`,
`gather_otherwise`, `gather_assignments`, and corresponding builders in
`to_annotated`.

- [ ] Replace local application/Lambda/Let/list/record/case peeling with
      `gleam_ir` spine views.
- [ ] Keep destructuring-pattern recognition in Morph.
- [ ] Preserve `from_annotated`'s multi-argument application normalization and
      deliberate bare-`Select` eta expansion.
- [ ] Decide whether malformed bare/partial primitives make `from_annotated`
      fallible or receive a total fallback; remove current printing, panic, and
      sentinel-variable behavior only with matching API and caller changes.
- [ ] Use canonical spine builders for Editable-to-IR conversion.
- [ ] Return safe fallback/error values for malformed partial primitives.
- [ ] Test proper/improper lists, extend/overwrite records, open cases, partial
      primitives, and multi-argument calls/functions.

### Morph analysis pairing

Target: `morph/analysis.do_analyse`.

- [ ] Encode Editable source once.
- [ ] Infer that exact tree.
- [ ] Replace `list.zip` with structural topology zip.
- [ ] Return an explicit analysis mismatch rather than silently truncating.
- [ ] Test every encoding topology and deliberate mismatch.

### Editable rendering

Target: `morph/lustre/render.expression`.

- [ ] Evaluate using the editable fold after site topology is stable.
- [ ] Keep layout decisions and HTML construction Morph-specific.
- [ ] Preserve error highlighting and path attributes.
- [ ] Remove assumptions that calls always contain arguments.
- [ ] Add snapshots for every Editable constructor and multiline forms.

## Phase 9: remaining cross-project refactorings

### Cross-package Let-spine helpers

Targets: `eyg/parser.do_gather`, `eyg/interpreter/block.inject`,
`eyg/cli/internal/source.block_expression`, and block reconstruction in
`eyg/cli/shell.type_of`.

- [ ] Use canonical metadata-aware Let-spine split/build operations.
- [ ] Preserve parser assignment order, vacant-tail handling, interpreter
      assignment execution order, and sentinel metadata.
- [ ] Test empty blocks, multiple assignments, vacant and non-vacant tails,
      interpreter scope order, and shell type queries with prior definitions.

### `touch_grass` AST flattening

Target: `touch_grass/eyg_parse.flatten`.

- [ ] Reimplement through canonical pre-order fold if exact prefix output remains
      clear.
- [ ] Preserve constructor tags and public `t.ast()` protocol.
- [ ] Use linear accumulation rather than repeated append.
- [ ] Add exact output for every constructor and nested Apply/Let.

### EYG package AST consumption

Targets: `eyg_packages/eyg/ast.eyg` parsing and rendering functions.

- [ ] Define canonical node arity for the flattened prefix protocol.
- [ ] Separate prefix-spine consumption from DAG-JSON rendering.
- [ ] Return errors for truncated and trailing inputs rather than silently
      manufacturing `Vacant`.
- [ ] Preserve exact encoded bytes and CIDs for valid input.
- [ ] Add missing `Overwrite` and `RelativeReference` tests.
- [ ] Run repository-level `eyg script entry.eyg` after every EYG package change.

### Website IR rendering

Target: `website/components/tree.do_print`.

- [ ] Evaluate an IR fold producing rendered lines.
- [ ] Preserve function/definition before argument/body.
- [ ] Preserve connector and indentation output.
- [ ] Add snapshots for all leaves and nested branching.

### Website hot reload pairing

Target: `website/components/reload.do_check_against_state`.

- [ ] Replace flattened annotation lists and `strict_zip` with topology zip.
- [ ] Return a controlled reload error rather than asserting.
- [ ] Preserve root metadata replacement after migration unification.
- [ ] Test unchanged, migrated, missing-field, and mismatch cases.

### Workspace module analysis

Targets: `website/routes/workspace/state.module_context`, `relative_cid`, and
`loaded_files`.

- [ ] Parse all loaded files before dependency analysis.
- [ ] Build an origin-aware relative module graph.
- [ ] Analyze dependency-first rather than using only the old module state.
- [ ] Replace fake CID inference identities with full relative identities where
      possible.
- [ ] Maintain reverse dependencies and reanalyze only affected modules.
- [ ] Test arbitrary load order, chains, cycles, missing files, same relative
      spelling in different directories, and leaf edits.

### Documentation example reanalysis

Targets: `website/routes/documentation/state.reanalyse_examples` and
`morph/buffer.add_references`.

- [ ] Keep a dependency index per buffer from the reference-site fold.
- [ ] Reanalyze reverse dependents instead of every buffer containing any error.
- [ ] Distinguish missing-reference errors from unrelated type errors.
- [ ] Match release completion by package/version identity as well as CID.
- [ ] Add unrelated-error, successful dependency, failed dependency, and release
      identity tests.

## Dependency and release updates

- [ ] If `eyg_hub` consumes the generic graph walker, add `topological` to
      `packages/gleam_hub/gleam.toml`; do not introduce an `eyg_ir` dependency
      into `topological`.
- [ ] Bump minimum `eyg_ir` versions in each migrated consumer only after the
      traversal/spine release containing the required API.
- [ ] Bump minimum `eyg_analysis` versions after the reference-aware context API
      is released.
- [ ] Use manifest package names (`eyg_ir`, `eyg_analysis`, and so on) in
      dependency and release instructions, while retaining `packages/gleam_*`
      only as filesystem paths.
- [ ] Keep `eyg_ir` free of upward dependencies and verify all newly consuming
      packages on their declared targets.

## Test and verification strategy

### Unit laws

- [ ] `map_children(identity)` preserves a node.
- [ ] `rewrite(identity)` preserves every constructor and metadata value.
- [ ] Metadata-only rewrite preserves topology and node count.
- [ ] Pre-order and post-order examples have fixed expected sequences.
- [ ] `Apply` always visits function before argument.
- [ ] `Let` always visits definition before body.
- [ ] First-error behavior follows documented order.
- [ ] Scope introduced for a child is restored after returning.
- [ ] `Let` labels are not in scope in their definitions.
- [ ] Structural zip succeeds exactly for compatible topology.
- [ ] Spine builders and views round-trip supported shapes.

### Graph laws

- [ ] A diamond loads and prepares the shared dependency once.
- [ ] Dependency-first output places every dependency before its dependents.
- [ ] A cycle error includes the closed cycle path.
- [ ] Missing and invalid references are distinct.
- [ ] Loaded source must hash to every pinned CID claiming it.
- [ ] Strict policy never resolves relative or unpinned references.
- [ ] Resolver-core tests run entirely against in-memory data.

### Package verification

- [ ] Run formatting, warnings-as-errors build, and tests for each changed Gleam
      package using `CONTRIBUTING.md` commands.
- [ ] Run both Erlang and JavaScript target suites for portable packages.
- [ ] Run `eyg script entry.eyg` for changes under `eyg_packages`.
- [ ] Add exact serialization and CID fixtures before changing codec traversal.
- [ ] Add generated JavaScript snapshots before changing compiler traversal.
- [ ] Add editor path/navigation property tests before consolidating Morph
      topology.
- [ ] Benchmark large and deep trees after core traversal migrations.

## Rollout order

1. Land traversal contracts and exhaustive `map_children` tests.
2. Land pure folds and rewrites without migrating semantic callers.
3. Migrate low-risk `gleam_ir` collectors and annotation helpers.
4. Correct and migrate free-variable handling.
5. Add reference-site operations and make inference preserve original reference
   constructors.
6. Add topology zip and migrate analysis pairing.
7. Add type-tree traversal and full reference identities in analysis.
8. Add resolver-driven graph traversal and sans-IO module preparation.
9. Integrate CLI hash/check/compile/share/publish.
10. Integrate strict hub validation.
11. Migrate compiler passes.
12. Consolidate Morph editable topology and paths.
13. Migrate serialization, rendering, workspace, and remaining consumers where
    the generic walk clearly improves correctness or maintenance.
14. Remove obsolete private recursive helpers only after compatibility and
    downstream tests pass.

## Completion criteria

- The child structure of raw IR is defined once in `gleam_ir`.
- Existing annotation, builtin, reference, release, and free-variable helpers
  use shared traversal foundations.
- Free-variable `Let` scope is correct and shared by IR, interpreter, and Morph.
- Analysis no longer relies on flatten-and-zip or a universal relative
  `vacant_cid` lookup.
- CLI type checking follows references transitively and can resolve local
  unpinned source.
- Hub validation follows pinned references transitively and rejects relative or
  unpinned source.
- Both use the same graph preparation and inference policy foundation.
- Cycles, missing modules, and incorrect pins have deterministic typed errors.
- Morph has one editable site order used by paths, focus, navigation, rendering,
  and analysis metadata.
- Every migrated package passes its required target builds and tests.
