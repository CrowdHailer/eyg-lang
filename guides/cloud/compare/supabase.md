---
name: EYG cloud compared with Supabase
description: How EYG cloud and Supabase differ, and which to choose.
---

# EYG cloud and Supabase

Supabase is an open source Postgres development platform: a database with authentication, storage, edge functions, realtime subscriptions, database webhooks and row level security, hosted or self hosted.

| | EYG cloud | Supabase |
| --- | --- | --- |
| Source | Open source | Open source |
| Data | Small named SQLite databases per workspace | A Postgres database per project |
| Access control | Effect policies, dataclips for shared queries | Row level security policies in SQL |
| Events | Chats, connections, webhooks, crons | Database changes, webhooks on changes, scheduled jobs |
| Code | EYG triggers and agents | Edge functions in TypeScript |

## Human agency

Row level security is a good example of policy as code: rules people can read, enforced for every query. EYG cloud applies the same idea to every effect, not only database rows. They work together: a database webhook can call a [webhook connection](../connections/webhooks.md), and a dataclip can query Supabase's API with a network secret.

## Choose Supabase when

- You are building an application backend and need a database, auth and storage.

## Choose EYG cloud when

- You want triggers and agents acting on events from many services, gated by policies, next to your backend.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
