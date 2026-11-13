---
name: Datalog proof trees
description: Explain interpreter query answers with matched facts, rule derivations and successful predicates.
slug: query-proofs
---

# Datalog proof trees

The Gleam EYG interpreter can return an ordinary evaluation result together with
**one finite proof tree per answer of each completed `resolve`**. This is an
opt-in host API in `eyg/interpreter/explain`; ordinary `resolve` still returns
the same deduplicated list of rows. The API uses the existing evaluator, indexes,
rule scheduling and fixed-point computation.

For example, an allowed page decision has this shape:

```text
Permit(actor: U_ADA, action: view, resource: /deployments) [rule 0]
├── Member(tenant: T_ACME, actor: U_ADA, role: C_PLATFORM)
└── RolePermission(tenant: T_ACME, role: C_PLATFORM,
                   action: view, resource: /deployments)
```

These children are the actual matched rows. The engine records which branch of
each join produced the head, so facts from rejected branches do not leak into a
successful answer. Rules with derived premises produce recursively nested trees.

## Host API

```gleam
import eyg/interpreter/explain
import eyg/parser

pub fn example() {
  let assert Ok(program) = parser.all_from_string(
    "resolve Out @{fact Input(1), rule Out(x) {var x Input(x)}}",
  )
  let started = explain.start(program, [])
  case explain.advance(started, 10_000) {
    explain.Completed(Ok(result), _steps) -> {
      // result.value is [1], represented as an interpreter Value.
      // result.queries contains Query("Out", [(1, Rule(... Fact("Input", 1)))])
      Ok(result)
    }
    explain.Completed(Error(_error), _steps) -> Error("Evaluation failed")
    explain.Suspended(_next, _steps) -> Error("Evaluation budget exhausted")
  }
}
```

Use `explain.advance(next, remaining_budget)` to resume a suspended evaluation.
Subtract the returned `steps` from the request's total budget. Suspension and
failure return **no completed explanation** and must not authorize an operation.
The budget counts interpreter transitions, not wall-clock time or allocated
memory; proof-map maintenance and builtins also do work within a transition.

## Evidence nodes

`eyg/interpreter/proof.Tree` has three constructors:

| Node | Evidence |
| --- | --- |
| `Fact(relation, row)` | A base fact in this resolution's input, or a row matched from a separate constant table |
| `Rule(relation, row, rule, at, premises)` | The completed derivation that first established this fact, with its matched premises in clause order |
| `Predicate(at, bindings)` | A lowered query guard that returned `True`, with its source metadata and visible scalar bindings |

Rule numbers are zero-based positions in the composed table's rule list and are
local to that `resolve`. Source metadata is retained from the IR; parser metadata
uses **UTF-8 byte offsets**. A guard's bindings are its visible strings, integers
and booleans. Generated names and non-scalar values are excluded. A predicate node
records the evaluated guard, not a symbolic proof of arbitrary code inside it.

Each `Query(relation, answers)` pairs every returned row with its tree. Empty
answers have an empty proof list. Resolutions are recorded in completion order;
nested and separate resolutions have separate stores and query records.
An inner resolution's proof is in its own record; arbitrary computation over its
returned list is not automatically expanded into an outer predicate's tree.

For the LLM quota example the rule's children are:

```text
Permit(U_ADA, /v1/inference, window: 2026-10) [rule 0]
├── Quota(limit: 50, same tenant/actor/endpoint/window)
├── Usage(used: 49, same tenant/actor/endpoint/window)
├── action == "infer"                      → True
├── nonnegative(used), used = 49            → True
└── used < limit, used = 49, limit = 50      → True
```

The comparison is displayed in human-readable form here; its recorded EYG source
is `!equal(!int_compare(used, limit), Lt({}))`. At 50/50 the guard fails: there is
no `Permit` answer and no successful proof tree. This API explains success; it
does not produce counterfactual denial trees.

## Recursion and alternatives

The engine keeps the **first discovered witness**, retaining base facts as leaves
even if rules could derive them too. A rule only reads its round's snapshot;
therefore every nested derived premise already has a finite witness. Cycles and
duplicate derivations do not grow evidence forever or change set semantics.
Alternative derivations of the same fact are not enumerated, and this is not a
shortest-proof search.

Proof candidates are committed only for facts actually returned by a completed
rule. A host-constructed rule returning a prebuilt constant table is recorded as
a zero-premise rule when it has no captured matches or guards. Input `Table`
values have no provenance attached: passing a previously computed fact back as
new input treats it as a new base assertion. The original table/value layout and
equality semantics are unchanged.

## Authorization integration

`packages/channel_policy` uses `authorize_with_proofs` to attach engine evidence
to each page or PR permission. Its quota example returns the guard evidence too.
The host rejects a nonempty permission list that has no corresponding engine
proof. The video renderer consumes these captured trees, not manually authored
proof diagrams.

Login/session validation, freshness, account linking, current-head review checks
and the requirement that **every** changed path is authorized remain explicit
Gleam host checks. They are labeled as host checks in the video rather than
represented as invented Datalog facts. A successful tree explains a derivation
from its input facts; the host establishes who may supply those facts.

This tracing API is currently provided by the Gleam interpreter. Compiled
JavaScript and SQLite query backends retain their normal value-returning APIs.

See the [channel-policy walkthrough](../packages/channel_policy/README.md) and
[engine tests](../packages/gleam_interpreter/test/eyg/interpreter/proof_test.gleam).
