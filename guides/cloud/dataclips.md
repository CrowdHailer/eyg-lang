---
name: Databases and dataclips
description: Give a workspace SQLite databases, and let channels without database access run reviewed queries by name.
---

# Databases and dataclips

A workspace has SQLite databases, and a dataclip is a named function, written in `workspace.eyg`, that runs with its own shell.
Channels that cannot touch a database can still call a dataclip, so a team can share answers from its data
without handing every channel, or every agent, raw SQL.
The name comes from Heroku Dataclips, saved queries that people share and run without database credentials.

## Databases

Programs use the same effects as the [CLI](../sqlite.md), `SQLite` to run one statement and `SQLiteQuery` to resolve a query table.

```eyg
perform SQLite({
  database: "links",
  sql: "SELECT author, text FROM links WHERE author = ?",
  parameters: [Text("alice")]
})
// Ok([[Text("alice"), Text("https://gleam.run/news")]])
```

On the cloud `database` is a name, not a path.
`links` is the file `databases/links.sqlite` in the workspace's data directory, next to its secrets,
a name is letters, digits, `_` and `-`, so a program cannot reach other files.
Parameters are always bound, never spliced into the SQL.

`shell.everything` answers both effects with an error, raw database access must be given on purpose.
`shell.with_databases(names, shell)` adds access to the named databases to a shell, for a trusted channel.

```eyg
{
  name: "links",
  config: (info) -> { {
    handle: cloud.handlers.for_channel(info),
    channel_shell: shell.with_databases(["links"], shell.everything),
    triggers: [save_links]
  } }
}
```

## Dataclips

A workspace's `dataclips` are records with:

| Field | |
| --- | --- |
| `name` | How channels call it |
| `description` | Optional, what it returns and the input it expects. Agents see it when they call a dataclip that does not exist |
| `shell` | The dataclip's own policy, usually `shell.databases(names)` |
| `clip` | A function from the input to the result |

```eyg
dataclips: [{
  name: "recent_links",
  description: "Messages with links shared in #links, oldest first, `{limit}` at most 50",
  shell: shell.databases(["links"]),
  clip: (input) -> {
    perform SQLite({
      database: "links",
      sql: "SELECT author, text FROM links ORDER BY rowid DESC LIMIT ?",
      parameters: [Integer(input.limit)]
    })
  }
}]
```

Any channel whose shell has the `dataclip` field calls it, `shell.everything` includes it.

```eyg
perform Dataclip({name: "recent_links", input: {limit: 5}})
// Ok(Ok([[Text("alice"), Text("Nice write up on BEAM schedulers https://example.com/beam")]]))
```

The outer result is the call, an error when there is no such dataclip or the clip fails.
The inner value is whatever the clip returns.

`shell.dataclips(names)` is a gate that allows only some dataclips, for example a channel for visitors:

```eyg
{handle: cloud.handlers.for_channel(info), channel_shell: {post: shell.pass, dataclip: shell.dataclips(["recent_links"]), ..cloud.reject_all}}
```

### What a dataclip can do

A dataclip runs with its `shell` and nothing else, the calling channel's shell does not apply inside it.
Its host has the workspace's databases and the effects of a computer, such as `Fetch` and `Now`, if its shell allows them.
It cannot post, read secrets, change files or call other dataclips.
Because a dataclip's shell is reviewed with its code, the question to ask in review is the usual one for a channel shell:
what is the most this function can do with any input.

### Why not give the channel read only SQL

Read only SQL still reads every row of every table.
A dataclip decides which rows and columns leave the database, can cap their number, and can validate its input,
`recent_links` never returns more than 50 rows whatever it is asked.
The same logic would be duplicated, and drift, in every channel that needs the answer.

## The example workspace

The [example workspace](../../examples/cloud/workspace.eyg) saves every message with a link posted in #links in the `links` database
with a trigger, #links is the only channel with access to it.
The `recent_links` dataclip lets every other channel, and their agents, ask what was shared.
Asked "What links were shared in #links recently?" in #general, the agent calls the dataclip and summarises the rows.

## Tracing

A dataclip's effects are traced as children of the `eyg.effect.Dataclip` span of the program that called it,
with the decision of the dataclip's own shell, see [tracing](./tracing.md).
