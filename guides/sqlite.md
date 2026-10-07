---
name: Querying SQLite
description: Resolve EYG query tables inside a SQLite database, with rules run as SQL joins.
---

# Querying SQLite

A query table can be resolved in memory with `resolve`, or inside a SQLite
database with the `SQLiteQuery` effect. The same rules work in both. In SQLite
each rule becomes one `INSERT ... SELECT` whose joins and filters use the
database's indexes, so queries stay fast over tables of hundreds of thousands of rows.

The [movies example](../examples/movies/) loads 36,273 films with 133,326 cast
credits from Wikipedia and queries them. [This recording](../examples/movies/movies.mp4)
edits one file from inline facts to the database, with the CLI running beside it.

## Two effects

The CLI provides two effects for SQLite files. A path is relative to the script
that performs the effect; `":memory:"` is one in memory database for the process.

`SQLite` runs one statement. Parameters are always bound, never spliced into the SQL.

```eyg
let rows = perform SQLite({
  database: "movies.sqlite",
  sql: "SELECT title FROM Movie WHERE year = ?",
  parameters: [Integer(1987)]
})
// Ok([[Text("84 Charing Cross Road")], [Text("Adventures in Babysitting")], ...])
```

Values are `Integer(Int)`, `Text(String)`, `Blob(Binary)` or `Null({})`.
Use it to create tables, load data and run SQL written by hand.

`SQLiteQuery` resolves a query table in the database.

```eyg
let star = "Arnold Schwarzenegger"
let query = @{
  rule CoStar({actor, title}) {
    var movie var actor var title
    Cast({movie, actor: star}),
    Cast({movie, actor}),
    Movie({id: movie, title})
  }
}
match perform SQLiteQuery({database: "movies.sqlite", query}) {
  Ok({facts, sql}) -> { resolve CoStar facts }
  Error(reason) -> { [] }
}
```

It returns the derived facts as a table, ready to `resolve` or to combine with
more rules in memory, and the SQL it ran. A relation that no rule derives, and
that has no inline facts, is read from the database table of the same name.
Record fields are column names. Relations that rules derive, or that have inline
facts, are temporary tables for the length of the query. If a database table has
the same name, its rows are copied into the temporary table first.

Every perform of `SQLiteQuery` shares one row type, so the type checker treats a
program as having one view of its databases.

## The generated SQL

The query above runs as:

```sql
INSERT OR IGNORE INTO temp."CoStar" ("actor", "title")
SELECT DISTINCT t1."actor", t2."title"
FROM "Cast" AS t0 CROSS JOIN "Cast" AS t1 CROSS JOIN "Movie" AS t2
WHERE t0."actor" = ? AND t1."movie" = t0."movie" AND t2."id" = t0."movie"
```

Each relation clause is a table in the join. The fields already bound when the
clause is reached become conditions on that table, the same key the interpreter
uses to look rows up in its index. Clauses join in the order they are written:
put the most selective clause first and index the columns it is joined on.
SQLite has no statistics for temporary tables and otherwise chooses full scans.

Rules are run in rounds until no rule inserts a row. A rule only runs again
when a relation it reads grew in the previous round. This supports recursion,
mutual recursion and rules that read several recursive relations, which a
single recursive CTE cannot express.

## What can be planned

Rule closures are partially evaluated. Values captured from the surrounding
program, and functions called in heads and predicates, are inlined. These become SQL:

| EYG | SQL |
| --- | --- |
| a variable bound by a clause | a column |
| an integer, string, binary or captured value | a bound parameter |
| `!equal(a, b)` | `a = b` |
| `match !int_compare(a, b) { Lt(_) -> ... }` | `a < b`, `a = b`, `a > b` |
| `match b { True(_) -> ... False(_) -> ... }` | `b`, `NOT b` |
| `!int_add`, `!int_subtract`, `!int_multiply` | `+`, `-`, `*` |
| `!string_append(a, b)` | `a \|\| b` |

Other builtins, lists, variants stored in a column and whole-row variables are
reported as errors before any SQL is run. Inline facts and derived rows must be
records of integers, strings, binaries or Booleans. A Boolean is stored as 1 or 0
and comes back as an integer.

## Performance

On the movies database, with indexes on `Cast(actor)` and `Cast(movie)`:

| Query | SQLite | Interpreter |
| --- | --- | --- |
| Arnold Schwarzenegger's co-stars after 1990 and everyone within two degrees of Kevin Bacon (11,224 facts) | 0.2s | 5s, after 12s building a 170k fact table |

The whole demo, `eyg run movies.eyg`, takes under half a second. Evaluation is
not semi-naive, a rule that runs again recomputes all of its rows.
