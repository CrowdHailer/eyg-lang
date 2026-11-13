---
name: EYG cloud compared with Heroku Dataclips
description: How EYG cloud and Heroku Dataclips differ, and which to choose.
---

# EYG cloud and Heroku Dataclips

Heroku Dataclips are saved SQL queries against a Heroku Postgres database. They are shared by URL with a team, run with read only access, and show results as a table or chart, or download them as CSV or JSON.

| | EYG cloud | Heroku Dataclips |
| --- | --- | --- |
| A dataclip is | A function with its own policy, called with an input | A saved SQL query |
| Who runs it | Programs, triggers and agents in any channel with the `dataclip` effect | People with the link or team access |
| Data | Named SQLite databases, and any API through `Fetch` | A Heroku Postgres database |
| Limits | The dataclip's shell, and the code: input checks, row caps | Read only credentials |

## Human agency

The idea is the same: give people answers from a database without giving them the database. EYG dataclips take an input and are programs, so they can validate it, cap results and combine sources, and an agent can call one when someone asks a question in chat. See [databases and dataclips](../dataclips.md).

## Choose Heroku Dataclips when

- Your data is in Heroku Postgres and people need shareable, up to date query results.

## Choose EYG cloud when

- Agents and automations should answer questions from data without raw database access.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
