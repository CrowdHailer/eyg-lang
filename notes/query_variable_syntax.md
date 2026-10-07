---
name: Query variable syntax, `var x` or `?x`
description: Pros and cons of marking query variables with `?x` at each use instead of declaring them with `var`.
date: 2026-10-07
---

Only this change is considered: how a rule says which names are query variables.
Lowering, `Match`, evaluation and SQL generation stay the same.

```eyg
// today
rule Out({director, title}) {
  var arnold var movie var title var dir var director
  Person({id: arnold, name: "Arnold Schwarzenegger"}),
  Cast({movie, person: arnold}),
  Movie({id: movie, title}),
  Directed({movie, person: dir}),
  Person({id: dir, name: director})
}

// proposed
rule Out({director: ?director, title: ?title}) {
  Person({id: ?arnold, name: "Arnold Schwarzenegger"}),
  Cast({movie: ?movie, person: ?arnold}),
  Movie({id: ?movie, title: ?title}),
  Directed({movie: ?movie, person: ?dir}),
  Person({id: ?dir, name: ?director})
}
```

## Quicker or simpler?

Evaluation is not quicker. Both forms lower to the same IR, with each variable bound by a lambda,
so the interpreter, the compiled JavaScript and the generated SQL are the same.
Parsing time is insignificant either way.

Some things are simpler:

- **Parser.** `query_variables` and the `var` keyword go away. `eyg/parser/query` no longer threads a
  `variables` list to decide if a name binds or compares. `?x` binds the first time it appears and compares after that.
  Every other expression is a constant.
- **Highlighting.** One TextMate regex (`\?[a-z_][a-z0-9_]*`) colours every query variable at every use.
  With `var` a grammar can only colour the declaration, because colouring the uses needs scope tracking that TextMate can't do.
- **Reading.** Whether `{e: movie}` binds `movie` or compares against a `movie` from the enclosing scope
  depends on a `var` line that may be several lines up. `?movie` makes that visible where it is used.

## Pros

- No declaration block. The Arnold query loses a line of five `var`s.
- Removes a silent shadowing hazard. If `var actor` is forgotten in a rule written inside
  `let {actor} = request`, `actor` becomes an equality test against the request, so the query returns
  different answers with no error. `?actor` can't collide with a lexical name.
- `?` can't occur in source identifiers, so lowering can use `?movie` as the IR variable name.
  This removes the need for generated names to avoid capturing lexical names.
- It looks like Datomic, DataScript and the InstantDB essay, which most readers of Datalog already know.
- `?` is unused in the lexer today, so this takes nothing from existing syntax.

## Cons

- **Typos become new variables.** Today a misspelt use (`moive`) isn't declared, so it's an unbound name
  and a compile error. With `?moive` it's a fresh variable, and the query quietly becomes a cross product.
  Prolog's fix is a singleton warning: a variable used exactly once is reported, and `?_` silences it.
  That check is needed for this to be safe.
- **Loses record punning.** `Edge({from, to})` is the common case today. The proposal needs
  `Edge({from: ?from, to: ?to})` or a new pun form `{?from, ?to}`. A new pun is more syntax to learn.
- **Head and guard expressions become a dialect.** Heads and guards are ordinary EYG expressions today:
  `{n: !int_add(n, 1)}`. With `?n` they can only be written inside a rule, and moving one into a helper
  function means renaming. Allowing plain `n` in heads means each variable has two spellings.
- **Steals a sigil.** `?` is a natural choice for a future try or optional operator.
- **Migration.** 111 `var` declarations across 12 files in `eyg_packages`, `examples` and `guides`.

## Recommendation

Worth doing only together with a singleton-variable check and a `{?from, ?to}` pun.
Without the check it trades a loud error (a typo) for a silent wrong answer.
That's the wrong way round for a language whose pitch is knowing what agents are doing.
