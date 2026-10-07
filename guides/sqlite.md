---
name: Querying SQLite
description: Compile a typed EYG table into SQL joins and a generated imperative client.
---

# Querying SQLite

`eyg/compiler/sql.to_sql(expression, relation, sources)` compiles a pure EYG
table expression into a SQLite query program and a JavaScript client. The
selected relation's inferred type supplies both the runtime decoder and a
TypeScript declaration. The caller specifies the **input database schema**;
there is no separately maintained output schema.

The [recorded demo](../examples/sqlite/demo.webm) shows a real file-backed SQLite
database: Alice inherits access to a report and its appendix, a newly inserted
child appears on the next query, and revoking her grant removes every result.
The same steps have executable assertions in
[demo.mjs](../examples/sqlite/demo.mjs).

## Run the example

Use Gleam, Bun for the generator, and Node.js 24 for the database client. The
demo was checked with Gleam 1.19.0 and Node.js 24.15.0. Database access uses
[Node's built-in SQLite module](https://nodejs.org/download/release/v24.15.0/docs/api/sqlite.html),
including scalar-function registration; no npm database driver is needed.

From the repository root:

```sh
cd packages/gleam_compiler
gleam run -m sqlite_demo --runtime bun
cd ../..
node examples/sqlite/demo.mjs
```

The generator reads [view.eyg](../examples/sqlite/view.eyg) and writes
`examples/sqlite/.generated/query.mjs` and `query.d.mts`. The demo creates an
isolated temporary database and deletes it on exit. It never opens a user's
existing database.

## The EYG view

The view combines a direct grant rule, recursive inheritance through `Child`,
and a projection of Alice's permissions. For example, its recursive rule is:

```eyg
rule Access({actor, resource: child, action}) {
  var actor var parent var child var action
  Access({actor, resource: parent, action}),
  Child({parent, child})
}
```

The full file supplies the other rules and binds the lexical constant `actor`.
Rule bodies and heads retain EYG's pure functions, structural equality, and
set semantics. Repeated variables and constants become checked predicates.
Cycles over a finite set of facts settle normally.

## The host contract

The [generator](../packages/gleam_compiler/test/sqlite_demo.gleam) calls the
compiler with `Source` mappings. For example:

```gleam
sql.Source("Child", "children", [
  sql.Column("parent", "parent", t.String),
  sql.Column("child", "child", t.String),
])
```

This declares `Child` to contain records with two string fields, read from the
corresponding SQLite columns. The host must choose trusted source mappings;
the compiler checks their consistency with the EYG view. Runtime reads reject
SQL values that violate that contract. Column and table identifiers are quoted;
relation names and fact values are bound parameters.

The compiler returns `Result(Query, String)`. `Query.result_type` is the inferred
selected row type; `Query.sql` contains the source SELECTs, rule INSERT/SELECTs,
and output SELECT with `%PREFIX%` placeholders. `Query.javascript` is a
self-contained ES module, and `Query.typescript` its declaration. The generated
module exports `run`, `decode`, and a `sql` preview that also includes temporary
table setup, snapshot, seeding, and cleanup statements. These statements form a
program: the client supplies parameters, registered functions, and iteration.
They are not a single standalone SELECT suitable for pasting into another SQL
engine.

For this view, the generated type is:

```typescript
export type Row = { resource: string; action: string };
```

An imperative caller opens its authorized connection and consumes the result:

```javascript
import {DatabaseSync} from 'node:sqlite';
import {run} from './.generated/query.mjs';

const db = new DatabaseSync('authorization.sqlite');
try {
  for (const row of run(db)) {
    console.log(row.resource, row.action);
  }
} finally {
  db.close();
}
```

No database effect was added to EYG. Database access belongs to this imperative
host; the view is pure and cannot open a connection. An embedding application
can expose an authorized database operation through its existing effect
boundary without granting query predicates access to that connection.

## Execution and decoding

SQLite reads each mapped table into a temporary fact set. Every round copies
that set into a snapshot, executes the generated SQL joins, and inserts new
facts with `INSERT OR IGNORE`. Pure EYG heads and guards run as registered
JavaScript scalar functions. A round that adds no facts ends evaluation.

This design supports mutual recursion and joins involving several recursive
relations. A single SQLite recursive CTE requires exactly one recursive table
reference in each recursive SELECT, so it cannot directly express all these
joins. See [SQLite's recursive CTE rules](https://www.sqlite.org/lang_with.html#recursive_common_table_expressions).
This implementation uses full snapshot rounds; it makes no claim of indexed
join-key optimization or semi-naive evaluation.

Canonical tagged JSON stored in temporary tables preserves the distinction
between records, tags, lists, and binaries. Record field order does not affect
deduplication. The generated decoder checks every field and variant before
returning JavaScript values:

| EYG value | JavaScript result |
|---|---|
| Integer | A safe integer `number` |
| String | `string` |
| Binary | `Uint8Array` |
| List(a) | Array of decoded `a` |
| Record | Object with the inferred fields |
| True / False | `boolean` |
| Other closed union | `{tag, value}` |

Input SQL columns support Integer, String, Binary, Boolean encoded as 0/1,
and one optional layer encoded as NULL or a scalar. Integers outside JavaScript's
safe range are rejected, including 64-bit SQLite integers that would otherwise
lose precision. Nested optional columns are rejected because NULL cannot
distinguish `None` from `Some(None)`.

## Boundaries and failure behavior

The expression must be pure, closed, and reference-free; resolve imports before
calling this API. Sources supply schemas for relation clauses inside rules;
they do not substitute a database during compile-time table construction.
The adapter accepts the positive rule lowering generated by query syntax.
Arbitrary hand-built rule closures that inspect an entire snapshot are rejected
instead of being treated as SQL joins. The selected result needs a concrete
data schema; unresolved type variables, open row tails, functions, and nested
tables cannot be decoded. Record fields beginning with `$` are reserved by the
JavaScript representation. Head/guard functions use the JavaScript compiler's
supported builtins; unsupported operations fail explicitly.

`run(db, {maxRounds: 1000, maxFacts: 100000})` is the default budget. Limits count
all composed relations, including input facts, and exceeding a limit throws
without returning partial permissions. Fact counts are checked after each seed
and rule statement; these limits are not hard bounds on temporary allocation.
Neither limit interrupts a divergent pure predicate or an expensive SQL join.
Hosts needing hard time or memory limits must run the client in an isolated
worker or process and enforce those limits there.

Each run uses a savepoint. Success drops its temporary tables; failure rolls
them back without discarding an enclosing caller transaction. Base tables are
read only. Functions are reused for repeat runs on the same client/connection.
Every invocation rereads the database, so deletion of an input grant removes
its derived access on the next invocation. A result is a snapshot, not a
long-lived permission token: the host must coordinate authorization and action
when concurrent revocation matters.

## Verification and recording

The compiler suite runs real Node SQLite tests for recursion, capture, schema
checks, decoding, limits, rollback, quoted identifiers, and record equality:

```sh
cd packages/gleam_compiler
gleam test --target javascript --runtime bun
```

To record the demo again, install Playwright with Chromium in your development
environment, generate the client, and run `node examples/sqlite/record.mjs` from
the root. An optional argument specifies an already-installed Playwright module
path. The recorder runs the live demo operations while displaying their actual
results, checks assertions, and writes `examples/sqlite/demo.webm`.
