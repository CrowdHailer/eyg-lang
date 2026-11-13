---
name: EYG cloud compared with Databricks
description: How EYG cloud and Databricks differ, and which to choose.
---

# EYG cloud and Databricks

Databricks is a data intelligence platform: a lakehouse for analytics and machine learning on open table formats, Lakebase, a managed Postgres for operational data synced with the lakehouse, and tools for building AI agents on governed data.

| | EYG cloud | Databricks |
| --- | --- | --- |
| Scale | A team's events and small databases | An organisation's data, at any size |
| Data | Act on events as they arrive, keep what triggers store | Bring data into one governed platform |
| Governance | Policies per channel and per dataclip | Unity Catalog across tables, models and agents |
| Hosting | Your own server | Databricks on your cloud provider |

## Human agency

Databricks gathers data into one governed platform, EYG cloud acts on events where they happen and keeps only what a trigger needs. Neither is right for every problem, see [errors and logs as triggers](../errors_and_logs.md) for the trade-offs of one database against several, and what Lakebase is.

## Choose Databricks when

- You need analytics, machine learning and governance across a large organisation's data.

## Choose EYG cloud when

- You want a team to react to events, errors and logs with triggers and agents, without building a data platform first.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
