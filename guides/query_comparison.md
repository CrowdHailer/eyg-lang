---
name: Query literals compared with Flix and Crepe
description: Where EYG's typed positive queries fit, and which query features remain outside their scope.
slug: query-comparison
---

# Query literals compared with Flix and Crepe

Reviewed against primary documentation on 2026-10-07. This is a language and
implementation comparison, not a performance benchmark. The EYG column describes
this repository's query implementation. “Unsupported” below means unsupported
inside the query language; all three host languages can express additional
algorithms outside their Datalog fragments.

## Shared ground

EYG queries are values. `fact`, `rule`, and `@{}` construct a `Table` whose row
type describes its relations; `resolve` evaluates the combined rules and selects
a relation. Lexical constants, record patterns, repeated variables, pure
predicates, and recursive joins cover the authorization tutorial. Types do not
prove termination or establish the authenticity of input facts.

Flix is the closest language-design comparison: constraint values can be passed
around and composed, their schemas are row polymorphic, and relation arguments
can themselves be polymorphic. It also provides `inject` for collections and
`solve ... project` for composing materialized results. EYG's `resolve` returns
a list; a fold can turn those results back into facts for another query.
[Flix fixpoints](https://doc.flix.dev/fixpoints.html).

Crepe expands `crepe!` programs into a Rust runtime and named relation structs.
Inputs are extended through generated typed APIs; running consumes the runtime
and returns output sets. In contrast, EYG can choose and combine rule values
at runtime without generating a new Rust program. Crepe's embedding makes it
a natural fit when the surrounding application and its data already live in
Rust. [Crepe macro API](https://docs.rs/crepe/0.2.0/crepe/macro.crepe.html).

## Queries Flix can state directly that EYG cannot

| Query | Flix | Current EYG |
| --- | --- | --- |
| Reachability over a finite graph | Recursive relation rules | Recursive relation rules |
| Members without a suspended account | Stratified negated relation | No negated relation clause |
| Least distance per destination during recursion | A lattice with minimum as its join | Set of distance facts; no lattice join |
| Abstract interpretation that joins conflicting signs | User-defined lattice operations | Ordinary facts; no lattice-valued relation |
| Reuse a materialized relation as another constraint value | `solve ... project` | Resolve a list, then fold it into facts |

Flix permits negation only when the composed dependency graph is stratified;
recursive dependency through negation is rejected. EYG's positive rules cannot
directly express “all `Member(x)` for which no `Suspended(x)` exists.” Resolve
the two finite relations and filter afterward, or have the trusted host supply
an `ActiveMember` relation. Negating a Boolean computed from a bound row is
different from testing the absence of a fact in an evolving database.
[Flix stratified negation](https://doc.flix.dev/stratified-negation.html).

Flix's lattice relations combine values associated with a key using declared
partial-order and join operations. Its examples include sign analysis and
shortest paths. EYG's set semantics retain each distinct distance instead of
replacing it with a minimum. Enumerating paths then taking a minimum is a
different algorithm and can diverge on cycles that keep producing distances.
Bounds and an explicit finite search are needed for that EYG formulation.
[Flix lattice semantics](https://doc.flix.dev/lattice-semantics.html).

Flix also has an effect system and user-defined handlers; EYG does not uniquely
combine logic and effects. Its host-interaction distinction is narrower:
EYG's runtime defines the available effects, whereas Flix documents primitive
machine effects that cannot be handled away. The choice matters when embedding
untrusted programs in an intentionally limited runtime.
[Flix introduction](https://doc.flix.dev/),
[Flix primitive effects](https://doc.flix.dev/primitive-effects.html).

## Crepe's extra query constructs and execution strategy

Crepe supports stratified negation, Rust expressions, conditional `let`
destructuring, and `for` iterator clauses. EYG supports pure expression heads
and guards, but its relation patterns bind variables and record fields; it has
no corresponding iterator clause or conditional Rust pattern syntax. A
producer can instead fold a finite collection into EYG facts before resolving.
Calling a Rust function is also not a static purity guarantee; EYG rejects
escaped effects in query heads and predicates.
[Crepe syntax extensions](https://docs.rs/crepe/0.2.0/crepe/macro.crepe.html#datalog-syntax-extensions).

Crepe documents semi-naive evaluation and automatically generated indices.
EYG evaluates rules in rounds against an immutable snapshot. Each clause finds
rows through a hash index on its bound fields, facts are sets, and a rule only
runs again when a relation it read grew. It is not semi-naive: a rule that runs
again recomputes all of its facts. Large data belongs in SQLite, where the same
rules run as joins (see the [SQLite guide](sqlite.md)). No throughput comparison with Crepe is claimed.
[Crepe project](https://github.com/ekzhang/crepe).

| Concern | EYG | Crepe |
| --- | --- | --- |
| Rule composition | Ordinary `Table` values | Rules fixed by macro expansion |
| Relation representation | Structurally typed values in named rows | Generated tuple structs |
| Host code in rules | Statically pure EYG; runtime escaped-effect check | Rust expressions and functions |
| Solver implementation | Indexed rounds, rules rerun when inputs grow | Semi-naive evaluation with indices |
| Negation | No relation negation | Stratified negation |
| Application boundary | Effects supplied by the embedding runtime | Rust application APIs |

## Implications for this implementation

The present scope is composable, typed **positive** queries embedded in EYG.
Neither negation, lattice semantics, nor parity with an optimizing Datalog
compiler is claimed. These are language-design choices, not missing syntax
aliases that can safely be added without changing the solver.

For authorization, prefer explicit allow facts and fresh trusted snapshots.
The tutorial models cancellation by requiring `state: "running"` and removing
revoked input facts, rather than depending on an absent-denial query. Large
graphs and unrestricted computed heads need explicit execution and input-size
limits. The implementation and test locations are linked below so these
comparisons can be revisited when the engine changes.

- [Parser and rule lowering](../packages/gleam_parser/src/eyg/parser/query.gleam)
- [Interpreter fixed-point evaluation](../packages/gleam_interpreter/src/eyg/interpreter/state.gleam)
- [JavaScript query runtime](../packages/gleam_compiler/src/eyg/compiler/js.gleam)
- [Query semantics tests](../packages/gleam_interpreter/test/eyg/interpreter/query_test.gleam)
- [Executable authorization tutorial](./authorization.md)
