# Tree and graph traversal tutorial

This tutorial explains the techniques used by the
[recommended walks plan](./recommended_walks.md). It is intended for an
experienced programmer who is comfortable with functions, loops, records,
variants, and simple recursion, but has not studied functional-programming
abstractions.

The goal is practical understanding. Terms such as `StateT`, catamorphism, and
open recursion are introduced only after the underlying code is clear.

Most snippets are schematic Gleam. They omit imports and some project-specific
error definitions so the traversal remains visible. Gleam's `#(a, b)` is a
tuple, `[item, ..rest]` prepends to a list, and `use value <- result.try(work)`
means: return immediately if `work` is `Error`; otherwise bind its successful
value and continue. Reusing a name in successive `let` bindings shadows the old
immutable value rather than mutating it.

The external Haskell links are optional advanced references. Their notation is
explained locally before it is relied upon.

## What you will learn

By the end, you should be able to explain and implement:

- A direct recursive tree walk.
- A fold that summarizes a tree.
- A rewrite that produces a changed tree.
- A state-threading walk.
- A fallible state-threading rewrite.
- The practical meaning of `mapAccumM` and `StateT`.
- A recursion callback and selective open recursion.
- Scope-aware traversal.
- Reference extraction and module graph traversal.
- Cycle detection, memoization, and dependency-first processing.
- Structural zipping of two trees.
- Paths and zippers for editing.
- Canonical views of repeated low-level tree encodings.
- Package boundaries that keep traversal pure and IO in adapters.





## 4. Fold: turn a tree into a summary

A fold separates recursive plumbing from the operation performed at each node.
Two useful operations are often both casually called "fold", but they have
different callback types and order:

- `fold_pre_order` threads an accumulator through parent then children.
- `fold_bottom_up` recursively computes children, then combines their results at
  the parent.

The earlier `collect_content_cids` is a pre-order accumulator fold. The next
example is a bottom-up fold.

### Bottom-up fold

For a recursive data type, a bottom-up fold means: recursively fold each child,
then combine the current constructor with the child results.

A reduced fold can be written as:

```gleam
fn fold_bottom_up(
  expression: Expr,
  leaf: fn(Expr) -> result,
  lambda: fn(String, result) -> result,
  apply: fn(result, result) -> result,
  let_: fn(String, result, result) -> result,
) -> result {
  case expression {
    Lambda(parameter, body) ->
      lambda(parameter, fold_bottom_up(body, leaf, lambda, apply, let_))

    Apply(function, argument) ->
      apply(
        fold_bottom_up(function, leaf, lambda, apply, let_),
        fold_bottom_up(argument, leaf, lambda, apply, let_),
      )

    Let(name, definition, body) ->
      let_(
        name,
        fold_bottom_up(definition, leaf, lambda, apply, let_),
        fold_bottom_up(body, leaf, lambda, apply, let_),
      )

    other ->
      leaf(other)
  }
}
```

Node count becomes a set of combining rules:

```gleam
fold_bottom_up(
  source,
  leaf: fn(_) { 1 },
  lambda: fn(_, body_size) { 1 + body_size },
  apply: fn(function_size, argument_size) {
    1 + function_size + argument_size
  },
  let_: fn(_, definition_size, body_size) {
    1 + definition_size + body_size
  },
)
```

Maximum depth is another use of the same recursion:

```gleam
fold_bottom_up(
  source,
  leaf: fn(_) { 1 },
  lambda: fn(_, body_depth) { 1 + body_depth },
  apply: fn(function_depth, argument_depth) {
    1 + int.max(function_depth, argument_depth)
  },
  let_: fn(_, definition_depth, body_depth) {
    1 + int.max(definition_depth, body_depth)
  },
)
```

## 5. Rewrite: turn a tree into another tree



## 6. Explicit state threading

Sometimes visits need to communicate. Examples include:

- Assigning deterministic node numbers.
- Allocating fresh compiler variable names.
- Remembering modules already prepared.
- Building a reference type dictionary.

An imperative implementation might update a mutable counter. A functional
implementation accepts the old state and returns the new state.

Number reference occurrences:

```gleam
fn number_references(
  expression: Expr,
  next: Int,
) -> #(List(#(Int, String)), Int) {
  case expression {
    ContentReference(cid) ->
      #([#(next, cid)], next + 1)

    ReleaseReference(_, _, cid) ->
      #([#(next, cid)], next + 1)

    RelativeReference(path) ->
      #([#(next, path)], next + 1)

    Lambda(_, body) ->
      number_references(body, next)

    Apply(function, argument) -> {
      let #(function_refs, next) = number_references(function, next)
      let #(argument_refs, next) = number_references(argument, next)
      #(list.append(function_refs, argument_refs), next)
    }

    Let(_, definition, body) -> {
      let #(definition_refs, next) = number_references(definition, next)
      let #(body_refs, next) = number_references(body, next)
      #(list.append(definition_refs, body_refs), next)
    }

    _ ->
      #([], next)
  }
}
```

This example uses `list.append` to keep the state flow easy to see. A production
collector should prepend into one threaded accumulator and reverse once, as in
section 2, to avoid repeated copying.

The repeated name `next` resembles assignment, but each binding is a new
immutable value. The data flow is explicit:

```text
initial state
  -> function traversal
  -> updated state
  -> argument traversal
  -> final state
```

Swapping function and argument changes numbering. Running both with the same
initial state would create duplicate numbers. State makes order semantically
important.

This is specifically a pre-order state walk. A bottom-up stateful rewrite is a
different API: it threads state through children first and lets the parent rule
see their rewritten results. Names such as `map_accum_pre_order` and
`rewrite_accum_bottom_up` make that distinction explicit.

### The `numberTree` reference

The [`numberTree` example](https://hackage.haskell.org/package/mtl-2.3.2/docs/Control-Monad-State-Strict.html#g:4)
uses the same technique through Haskell's `State` abstraction. It carries a
table of previously seen values, assigns each new value a position, then passes
the updated table through both subtrees.

The example is worth reading in this order:

1. `numberTree` defines tree recursion.
2. `numberNode` reads and updates the table.
3. `nNode` is the ordinary pure table operation.
4. `evalState` supplies the initial empty table and discards the final table.

Haskell notation used there:

- `do` sequences operations in order.
- `value <- operation` binds the successful value produced by an operation.
- `get` reads current state.
- `put new_state` replaces current state for later operations.
- `return value` produces a value without changing state; it does not return
  from the enclosing function in the imperative sense.
- `Eq a =>` means the element type supports equality.

Nothing about tree recursion requires a monad. `State` packages the explicit
function shape so repeated state plumbing is less visible.

### Exercise

Annotate every node, not only references, with a pre-order integer. Test the
exact numbers of the running example.

### Combine state, rewriting, and failure

Resolve relative references and count how many were replaced:

```gleam
fn resolve_and_count(
  expression: Expr,
  count: Int,
  lookup: fn(String) -> Result(String, ResolveError),
) -> Result(#(Expr, Int), ResolveError) {
  case expression {
    RelativeReference(path) -> {
      use cid <- result.try(lookup(path))
      Ok(#(ContentReference(cid), count + 1))
    }

    Apply(function, argument) -> {
      use #(function, count) <-
        result.try(resolve_and_count(function, count, lookup))
      use #(argument, count) <-
        result.try(resolve_and_count(argument, count, lookup))
      Ok(#(Apply(function, argument), count))
    }

    Let(name, definition, body) -> {
      use #(definition, count) <-
        result.try(resolve_and_count(definition, count, lookup))
      use #(body, count) <-
        result.try(resolve_and_count(body, count, lookup))
      Ok(#(Let(name, definition, body), count))
    }

    Lambda(parameter, body) -> {
      use #(body, count) <-
        result.try(resolve_and_count(body, count, lookup))
      Ok(#(Lambda(parameter, body), count))
    }

    leaf ->
      Ok(#(leaf, count))
  }
}
```

This one function:

- Walks the tree.
- Rebuilds the tree.
- Threads state.
- Performs lookup.
- Stops on failure.

Its essential type is:

```gleam
fn(node, state) -> Result(#(node, state), error)
```

### What happens to state after an error?

This shape does not return state on failure:

```text
state -> Result(#(value, state), error)
```

This alternative does:

```text
state -> #(Result(value, error), state)
```

Neither is always correct. For source rewriting, discarding partial state is
usually clearer. For diagnostics, preserving all work before failure may be
useful. Choose and document the behavior rather than assuming they are the
same.

## 8. `mapAccumM` and `StateT` in plain language

The Haskell function
[`mapAccumM`](https://hackage.haskell.org/package/base-4.22.0.0/docs/Data-Traversable.html#v:mapAccumM)
gives a standard name to the ordered action-and-state part of the previous
pattern:

```haskell
mapAccumM
  :: (s -> a -> m (s, b))
  -> s
  -> t a
  -> m (s, t b)
```

Read it from right to left:

1. Start with a traversable structure `t a`.
2. Start with state `s`.
3. For each `a`, run an operation using the current `s`.
4. The operation returns updated `s` and replacement `b` inside effect `m`.
5. Return final state and the rebuilt `t b`.

In this notation, `::` means "has type", `=>` introduces requirements on type
parameters, `m value` means a value in some effect, and `(a, b)` is a tuple.
`Monad` alone does not mean failure: failure is available only when `m` is a
specific type such as `Either error` (the Haskell analogue of `Result`).

For the EYG walk:

| Haskell part | EYG meaning |
| --- | --- |
| `t a` | IR structure being traversed |
| `a` | visited node or selected reference site |
| `b` | rewritten node |
| `s` | counter, cache, type dictionary, or reached modules |
| `m` | A chosen effect; `Result(_, error)` for this EYG use |

EYG's walk is `mapAccumM`-like, not a direct implementation. Haskell's
`Traversable` preserves an already-contained shape. EYG may load another module
through a reference and recurse into source that was not contained in the
original tree, and a general EYG rewrite can replace a node with different
topology. Haskell returns `(state, value)` while these EYG examples return
`#(value, state)`.

`StateT` describes a related function shape:

```text
StateT state effect value
  approximately equals
fn(state) -> effect(#(value, state))
```

Substitute EYG types:

```text
StateT ReferenceCache Result Node
  approximately equals
fn(ReferenceCache) -> Result(#(Node, ReferenceCache), Error)
```

You do not need to implement `StateT` in Gleam to use the idea. Explicit state
arguments are often easier to read and debug.

## 9. Open recursion and recursion callbacks

Normal recursion fixes recursive calls inside the function:

```gleam
fn closed_size(expression: Expr) -> Int {
  case expression {
    Lambda(_, body) -> 1 + closed_size(body)
    // ...
  }
}
```

Open recursion makes the recursive operation an input:

```gleam
fn walk(
  expression: Expr,
  visit: fn(Expr, fn(Expr) -> result) -> result,
) -> result {
  visit(expression, fn(child) { walk(child, visit) })
}
```

The handler receives `recurse`. It can:

- Recurse normally.
- Skip a subtree.
- Change child order.
- Recurse into a replacement.
- Recurse into newly loaded source.

A reusable structural descent can still own ordinary children:

```gleam
fn descend(expression: Expr, recurse: fn(Expr) -> Expr) -> Expr {
  map_children(expression, recurse)
}
```

### Why references need the callback

At a relative reference, hashing must:

1. Locate and load the referenced file.
2. Walk the loaded module so its own references become pinned.
3. Hash that rewritten module.
4. Replace the relative reference with the resulting content reference.

At the same reference, checking must:

1. Load the referenced module.
2. Walk its dependencies first.
3. Infer its polymorphic type.
4. Add that type to the reference environment.
5. Check the parent source.

The generic structural walk cannot know these policies. Passing `recurse` lets
the policy request the same traversal for loaded source.

The current
[test prototype](../packages/gleam_cli/test/eyg/cli/internal/reference_walk_test.gleam)
demonstrates this shape. It is deliberately incomplete as production graph
code: its strict mode does not yet reject relative references, and it has no
module memoization or cycle detection.

### `mcata`

[`mcata`](https://hackage.haskell.org/package/recursion-schemes-5.2.3/docs/Data-Functor-Foldable.html#v:mcata)
is a formal example of supplying recursion to a handler:

```haskell
mcata :: (forall y. (y -> c) -> f y -> c) -> Fix f -> c
```

The `(y -> c)` argument is the recursive capability. EYG borrows this pattern,
but is not literally an `mcata`: the callback may receive an externally loaded
concrete IR tree, carries state, and can fail. Mendler typing restricts recursion
to abstract child positions; the concrete EYG callback does not impose that
restriction or provide a general termination guarantee.

### Callback, not continuation

A continuation represents what remains after the current operation. Calling it
continues toward the final result.

The EYG `recurse` argument starts the walk on a supplied tree. It is therefore a
recursion callback, not a continuation. This distinction becomes important when
the type checker later uses real suspension continuations to request missing
inputs.

### Common mistake

Calling `recurse` on the unchanged current node creates infinite recursion:

```gleam
fn bad_rule(node, recurse) {
  recurse(node)
}
```

Call it only on structural children, a replacement whose revisit is intended,
or separately loaded source.

### Alpha renaming

Compiler alpha renaming combines inherited scope with threaded state:

- Scope maps source names to current generated names.
- State supplies the next fresh number.
- A Let definition sees old scope.
- A Let body sees scope extended with its generated binder.
- Updated fresh-number state continues after each child.

This is a good example of why context and state should be separate concepts.

### Exercise

Implement `occurs_free(name, expression)` with early exit. Test a Let
definition, Let body, nested Lambda shadowing, and a free occurrence in an
`Apply` argument.

### Type expressions are trees too

`eyg_analysis` has another recursive data type for inferred types. Its branching
constructors include functions, row extensions, effect extensions, lists,
records, unions, and promises. The same one-layer/fold/state patterns apply, but
the operation-specific `Var` case remains in analysis:

- `resolve` follows a variable that is bound to another type.
- `gen` decides whether an unbound variable becomes quantified at a level.
- `instantiate` threads fresh-variable state so repeated quantified IDs receive
  the same replacement.
- Occurs checking uses a fallible traversal that stops when a type contains the
  variable being bound.

This is why `eyg_ir` should not provide one universal traversal for all recursive
types. It defines raw IR topology; `eyg_analysis` defines type topology and type
semantics.

## 11. Reference sites and identity

EYG has three syntactic reference forms:

```gleam
pub type Reference {
  Content(cid: String)
  Release(package: String, version: Int, cid: String)
  Relative(path: String)
}
```

A useful reference-site walk should preserve every occurrence and its metadata.
Do not deduplicate in the primitive operation:

- Two occurrences can need separate source diagnostics.
- The same relative spelling can resolve differently in two source origins.
- An unpinned release must not be treated as content with `vacant_cid`.

Deduplication is a policy applied later when fetching or uploading modules.

### Full identities

Content identity is a CID. Release identity includes package, version, and its
declared CID. Relative identity requires both path and importing origin.

```text
Relative("./helper.eyg", origin = "src/one/main.eyg")
Relative("./helper.eyg", origin = "src/two/main.eyg")
```

These may identify different files. A type dictionary keyed only by path or a
shared vacant CID cannot distinguish them.

Resolution and prepared-module caching need two levels of identity:

- A **resolution key** includes release selectors or origin-qualified relative
  paths. It determines what source should be loaded.
- After loading and verifying immutable source, its **content key** is the CID.
  Different release/content selectors that resolve to the same CID can share one
  prepared result.

Using only the resolution key duplicates shared immutable work. Using only the
CID cannot resolve an unpinned release or relative path correctly.

Resolving `Release(package, 0, vacant_cid)` must return both a concrete version
and CID. A pinned rewrite changes both fields. Adding a CID while retaining
version `0` still contains a mutable "latest" selector and is not fully pinned.
Strict hosted policy rejects version `0` even if a CID is present.

## 12. A module graph is not an IR tree

Inside one module, structural recursion is enough. Once references are followed,
the structure can contain sharing and cycles.

A diamond graph has shared work:

```text
A -> B -> D
|         ^
`-> C ----'
```

`D` should be loaded, pinned, and checked once.

A cycle never reaches a leaf:

```text
A -> B -> C -> A
```

Plain recursion would continue forever.

### Three-state depth-first search

Use three logical states:

```text
Unseen: no work has started
Visiting: work started, dependencies incomplete
Done(result): preparation completed
```

The algorithm is:

```text
prepare(key, path, cache):
  if cache[key] is Done(result):
    return result and cache

  if cache[key] is Visiting:
    return Cycle(path closed with key)

  load key
  mark key Visiting

  for each reference in loaded source:
    prepare dependency using updated cache

  rewrite/check the loaded source
  mark key Done(result)
  return result and cache
```

The `Visiting` state detects back edges and cycles. `Done` prevents duplicate
work. A single `visited` set is insufficient because it cannot distinguish a
completed shared dependency from one currently on the recursion stack.

### Dependency-first results

Hashing and checking need children before parents:

- A relative dependency must be pinned before the parent CID is computed.
- A dependency type must be known before the parent reference can be inferred.
- Upload should send dependencies before source that points at them.

This is post-order across the module graph, even if each source tree uses a
different internal node order.

### Topological sorting

For this plan, an edge `A -> B` means "A depends on B", and dependency-first
output must place `B` before `A`. The existing `topological.sort` API documents
the opposite useful presentation order, so preserve it and add a new API or
deliberately reverse its result at the module-preparation boundary. The
`topological` package can own generic cycle and ordering mechanics. It should
not know what a module, CID, type, or HTTP request is.

### Exercise

Implement the three-state algorithm against an in-memory dictionary. Count
resolver calls and prove the diamond's `D` is loaded once. Return
`[A, B, C, A]` or equivalent for a closed cycle path.

## 13. Recursive type checking of references

The existing inference algorithm can type a reference when its polymorphic type
is already in the context. The missing operation is dependency preparation.

For one module:

```text
prepare source references
  -> prepare each referenced module recursively
  -> infer each dependency
  -> add dependency Poly type to reference environment
  -> infer parent source
```

The CLI and server differ only in policy:

| Local CLI policy | Hosted server policy |
| --- | --- |
| May read relative files | Rejects relative references |
| May resolve unpinned releases | Rejects unpinned releases |
| Returns rewritten pinned source | Requires source already pinned |
| Uses filesystem and HTTP adapters | Uses database adapter |

They should share:

- Tree reference extraction and rewriting.
- Graph states and cycle detection.
- CID verification.
- Dependency-first inference.
- Error types.
- Prepared-result caching.

The resolver is injected. The shared algorithm does not import filesystem,
HTTP, PostgreSQL, or JavaScript promises.

Local relative resolution still requires a directory-bearing source origin. A
file can provide one; inline code, stdin/pipe input, and a REPL fragment cannot
unless the command explicitly supplies a base. Published content/release source
must not acquire accidental meaning from the server or CLI process directory.
Those cases return source-aware resolution errors.

### Callback versus request protocol

A lookup callback is simple:

```gleam
fn prepare(
  source,
  lookup: fn(Reference) -> Result(Module, Error),
) -> Result(Prepared, Error)
```

But the callback may hide IO and can be awkward when one target is synchronous
and another is asynchronous. A sans-IO step protocol makes missing work data:

```gleam
pub type Preparation(result) {
  Need(
    reference: Reference,
    resume: fn(Result(Module, LookupError)) -> Preparation(result),
  )
  Complete(result)
  Failed(error: PrepareError)
}
```

The CLI or server drives requests. The core preparation remains deterministic
and testable with in-memory modules. Choose between callback and step protocol
based on adapter needs, not terminology.

## 14. Structural zip

Sometimes two trees should have the same topology but different metadata. Type
inference, for example, produces an analyzed tree corresponding to source.

A tempting implementation flattens both trees and zips the lists. This is
unsafe:

- Different trees can contain the same node count.
- A non-strict zip can silently truncate.
- A mismatch loses its parent/child location.

A structural zip walks in lockstep:

```gleam
fn same_branching_shape(left: Expr, right: Expr) -> Bool {
  case left, right {
    Lambda(_, left_body), Lambda(_, right_body) ->
      same_branching_shape(left_body, right_body)

    Apply(left_function, left_argument),
      Apply(right_function, right_argument) ->
      same_branching_shape(left_function, right_function)
      && same_branching_shape(left_argument, right_argument)

    Let(_, left_definition, left_body),
      Let(_, right_definition, right_body) ->
      same_branching_shape(left_definition, right_definition)
      && same_branching_shape(left_body, right_body)

    Lambda(_, _), _ | Apply(_, _), _ | Let(_, _, _), _ ->
      False

    _, Lambda(_, _) | _, Apply(_, _) | _, Let(_, _, _) ->
      False

    _, _ ->
      True
  }
}
```

A production version should return a mismatch containing:

- Path to the mismatch.
- Left constructor.
- Right constructor.
- Optional metadata from both sides.

The example checks only recursive branching, so `Variable` and `Integer` are
compatible leaves. Production APIs should name three distinct modes:

- **Child topology**: recursive arity and child positions match; leaves may
  differ.
- **Constructor topology**: constructors match but metadata/payloads may differ.
- **Exact syntax**: constructors and payloads match; metadata policy is explicit.

Pairing source metadata with analysis metadata can use child topology while
inference changes reference leaves, then move to constructor topology once
inference preserves them. A structural diff normally needs constructor or exact
syntax comparison.

### Exercise

Construct two trees with equal node counts but different topology. Make a flat
length check pass and structural zip fail at a precise path.

## 15. Paths and zippers

A path identifies how to descend from a root:

```gleam
pub type Step {
  LambdaBody
  ApplyFunction
  ApplyArgument
  LetDefinition
  LetBody
}

pub type Path =
  List(Step)
```

For the running example, the content reference path is:

```text
[LetBody, ApplyArgument]
```

Paths are useful for diagnostics, editor selections, and locating metadata.
They can become stale after structural changes.

A zipper stores the focused node plus everything needed to rebuild its parents:

```gleam
pub type Crumb {
  InLambda(parameter: String)
  InApplyFunction(argument: Expr)
  InApplyArgument(function: Expr)
  InLetDefinition(name: String, body: Expr)
  InLetBody(name: String, definition: Expr)
}

pub type Zipper {
  Zipper(focus: Expr, context: List(Crumb))
}
```

Move upward by rebuilding one parent:

```gleam
fn up(zipper: Zipper) -> Result(Zipper, Nil) {
  let Zipper(focus, context) = zipper

  case context {
    [] ->
      Error(Nil)

    [InLambda(parameter), ..rest] ->
      Ok(Zipper(Lambda(parameter, focus), rest))

    [InApplyFunction(argument), ..rest] ->
      Ok(Zipper(Apply(focus, argument), rest))

    [InApplyArgument(function), ..rest] ->
      Ok(Zipper(Apply(function, focus), rest))

    [InLetDefinition(name, body), ..rest] ->
      Ok(Zipper(Let(name, focus, body), rest))

    [InLetBody(name, definition), ..rest] ->
      Ok(Zipper(Let(name, definition, focus), rest))
  }
}
```

Useful laws are:

```text
move down then up reconstructs the original tree
replacing focus changes only that path
focus_at(root, path) either succeeds exactly or returns a path error
forward site traversal reversed equals reverse traversal
```

Morph's Editable tree contains more than expression children: patterns, field
labels, branch labels, and optional tails are editable sites. Those must have
one canonical order shared by paths, focus, next/previous navigation, rendering,
and generated IR metadata.

## 16. Canonical spine views

Some high-level syntax is encoded as repeated low-level IR nodes.

A call with three arguments is nested left-associated application:

```text
Apply(Apply(Apply(function, first), second), third)
```

A helper can expose the high-level view:

```text
view_call(source) -> #(function, [first, second, third])
```

Similarly:

- Nested `Lambda` nodes form a multi-parameter function.
- Nested `Let` nodes form a block.
- `Apply(Apply(Cons, item), tail)` forms a list spine.
- Extend/overwrite applications form records.
- Case applications form match branches.

Why centralize these views?

- Morph, compiler rendering, parser block handling, and other consumers should
  agree on order and malformed forms.
- Partial applications must not be mistaken for complete high-level syntax.
- Builders and views can be tested as round trips.

Application decomposition itself is total: a non-`Apply` expression decomposes
to itself plus an empty argument list. Specialized list, record, and case views
should return `Option` or `Result` when a tree is not their complete encoding.
They should preserve improper list tails, record overwrite originals, and open
case fallbacks rather than silently discarding them.

### Exercise

Implement an application-spine view and builder. Test a non-call decomposing to
zero arguments plus calls with one and three arguments, and prove
`build_call(view_call(tree)) == tree` for supported shapes.

## 17. Which abstraction belongs where?

Package boundaries are part of correctness. A reusable function becomes less
reusable when it imports one runtime's IO.

### `gleam_ir`

Owns facts true for every consumer of the IR:

- Which constructors have structural children.
- Pure folds and rewrites.
- Explicit state/failure variants.
- Syntactic scope rules.
- Reference constructors as syntax.
- Structural topology.
- Canonical encoded spines.

It should not load files, call HTTP, query databases, infer types, or execute
programs.

### `gleam_analysis`

Owns type-specific meaning:

- Type-tree traversal.
- Unification and inference state.
- Effect contexts.
- Reference type environments and errors.
- Requests for reference types.

It can consume IR traversal but should remain pure and browser-compatible.

### `topological`

Owns graph mechanics that do not mention EYG:

- Resolver-driven depth-first traversal.
- Temporary and permanent visit states.
- Cycle paths.
- Dependency order.

### `gleam_hub`

Owns sans-IO module policy:

- A module is sound and pure.
- Hosted references are pinned.
- Loaded source matches declared CID.
- Dependencies are prepared before parents.
- Shared preparation errors and caches.

### `gleam_cli` and `hub`

Own concrete adapters:

- CLI: files, source origins, HTTP client, SHA-256, terminal diagnostics.
- Server: PostgreSQL, HTTP responses, persistence.

Both drive shared preparation rather than implementing separate graph recursion.

### `gleam_compiler`

Owns transformation rules such as alpha renaming, Let normalization, monadic
lowering, and fresh-name policy. It can use generic rewrites but should not move
those semantics into `gleam_ir`.

### `gleam_interpreter`

The evaluator is a demand-driven continuation machine, not a whole-tree walk.
Only static queries such as free variables should reuse traversal helpers.

### `morph`

Owns Editable topology, editor paths, zippers, patterns, labels, navigation, and
rendering rules. Raw IR traversal cannot describe all Editable sites.

### How repository migrations map to these patterns

| Existing work | Traversal pattern |
| --- | --- |
| IR annotations, builtins, references, flat AST output | Pre-order fold |
| DAG-JSON encoding and tree rendering | Bottom-up fold where it stays auditable |
| Release mapping and compiler normalization | Bottom-up rewrite |
| Compiler fresh names and type instantiation | Stateful traversal |
| Free variables, closure capture, alpha renaming | Scope-aware traversal, sometimes plus state |
| Reference pinning and recursive checking | Reference-site rewrite plus module graph walk |
| Analysis/source metadata pairing | Structural topology zip |
| Morph focus and next/previous navigation | Editable-site walk plus zipper |
| Calls, functions, blocks, lists, records, and cases | Canonical spine views/builders |
| Parser/interpreter/CLI block helpers | Canonical Let-spine split/build |
| Workspace incremental analysis | Module graph plus reverse-dependency index |

The generic walk removes constructor plumbing. The domain package still owns
what the operation means, its errors, and its tests.

## 18. Capstone: one preparation pipeline

Combine the ideas into a reference-aware module preparation service.

### Data

```gleam
pub type Policy {
  ResolveLocal
  RequirePinned
}

pub type VisitStatus(prepared) {
  Visiting(path: List(Reference))
  Done(prepared)
}

pub type Prepared {
  Prepared(
    pinned_source: Expr,
    cid: String,
    type_: Poly,
  )
}
```

### Algorithm

```text
State has two indexes:
  resolutions: ResolutionKey -> Resolving(path) | Resolved(content CID)
  prepared: ContentCID -> Visiting(path) | Done(Prepared)

prepare_reference(site, origin, policy, state):
  validate site against policy
  derive ResolutionKey from release selector or origin-qualified relative path

  if resolutions[key] is Resolving:
    return a cycle through that key

  if resolutions[key] is Resolved(cid) and prepared[cid] is Done:
    return the cached Prepared value

  mark resolutions[key] Resolving before loading or following dependencies
  resolve site to source, selected release version, and any declared content CID

  if a declared CID is known:
    verify loaded bytes/source immediately
    if prepared[cid] is Visiting, return a content cycle
    if prepared[cid] is Done, alias resolutions[key] to cid and reuse it
    mark prepared[cid] Visiting

  recursively prepare the loaded source exactly once
  this returns pinned source, inferred type, and its final computed CID

  if a declared CID was known, require final CID to equal it
  mark prepared[final cid] Done with the complete Prepared result
  replace resolutions[key] Resolving with Resolved(final cid)
  return the complete Prepared result

prepare_source(source, origin, policy, state):
  walk the source tree in canonical order

  for each reference site:
    call prepare_reference
    add its already-inferred Poly type to the environment
    rewrite the site using its concrete version and CID

  infer rewritten parent using prepared dependency types
  compute parent CID
  return rewritten source, type, CID, and final cache
```

A local root file also needs an origin-qualified resolution key inserted as
`Resolving` before `prepare_source` starts. Otherwise a relative import that
returns to the root cannot be recognized as a cycle. For relative source, the
final CID cannot be known until its own references have been rewritten. For a
content or pinned release reference, the declared CID is known and can be
verified before dependency traversal.

### Hash use

The hash command selects `ResolveLocal`, prepares all relative and unpinned
references, then prints the CID of `pinned_source`.

### CLI check use

CLI check selects `ResolveLocal`, prepares dependencies, checks the root with the
resulting type environment, and can report which releases were selected.

### Server check use

The server selects `RequirePinned`. It rejects relative and unpinned reference
sites before attempting to resolve latest state. It loads pinned CIDs from the
database, verifies them, checks dependencies, then validates root soundness and
purity.

Only policy and resolver adapters differ. Tree order, graph handling, pin
verification, inference order, and error types are shared.

## 19. Testing checklist

Test traversal behavior, not only final examples:

- Identity child mapping preserves every constructor and metadata value.
- Identity rewrite preserves the tree.
- Parent/child order is fixed for pre-order and post-order operations.
- `Apply` visits function before argument.
- `Let` visits definition before body.
- First failure follows documented order.
- State from the first child reaches the second child.
- Scope introduced for a child does not leak after returning.
- A Let binder is absent from its definition and present in its body.
- Duplicate reference sites retain separate metadata.
- A diamond module graph prepares its shared leaf once.
- A cycle reports the complete cycle.
- Pinned source is verified against its CID.
- Strict policy rejects relative and unpinned references.
- Structural zip rejects equal-sized but differently shaped trees.
- Every zipper descent can move back up and reconstruct the root.
- Spine builders and views round-trip valid encodings.
- Resolver-core tests use only in-memory data.

## 20. Suggested exercises in order

1. Count all nodes with direct recursion.
2. Collect builtin names with an accumulator.
3. Implement one-layer `map_children` and its identity tests.
4. Implement maximum depth through a fold.
5. Rewrite one old builtin spelling.
6. Assign pre-order IDs by threading an integer.
7. Resolve relative references with `Result` and a counter.
8. Fix first-error order with tests.
9. Implement free-variable detection with correct Let scope.
10. Add a recursion callback that can walk loaded module source.
11. Add `Visiting`/`Done` graph states and a diamond test.
12. Add dependency-first type preparation.
13. Implement structural zip with mismatch paths.
14. Implement a call-spine view and builder.
15. Implement a zipper replacement and round-trip tests.
16. Drive the complete preparation algorithm with an in-memory resolver.
17. Add separate local and strict policies without duplicating recursion.

## Further reading summary

- Start with
  [`numberTree`](https://hackage.haskell.org/package/mtl-2.3.2/docs/Control-Monad-State-Strict.html#g:4)
  for a concrete state-threaded tree transformation.
- Read
  [`mapAccumM`](https://hackage.haskell.org/package/base-4.22.0.0/docs/Data-Traversable.html#v:mapAccumM)
  for the standard abstract shape combining map, state, and sequencing; choose
  `Either` when failure is required.
- Read
  [`mcata`](https://hackage.haskell.org/package/recursion-schemes-5.2.3/docs/Data-Functor-Foldable.html#v:mcata)
  to see a recursion handler receive the recursive operation explicitly.
- Read
  [Closed and Open Recursion](https://www.cs.ox.ac.uk/ralf.hinze/talks/Open.pdf)
  for the broader design vocabulary.

The useful progression is direct recursion first, then fold/rewrite, explicit
state and failure, recursion control, scope, graph traversal, structural zip,
and finally package architecture. The abstractions are names for patterns you
already understand at each previous stage.
