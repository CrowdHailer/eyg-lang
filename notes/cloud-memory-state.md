---
name: Cloud state stays in memory
description: Cloud state is actor-owned; host storage is not a persistence backend.
date: 2026-11-13
---

Cloud sessions, private file roots, history, users, secrets, edited configuration
and artifacts stay in memory. The intended deployment shares state across a
cluster; this branch does not implement replication or recovery after all owners
stop. Do not substitute local JSON snapshots, SQLite files or writable volumes.

Startup configuration, trusted imports, static pages and initial seed files may
be read from the application image. Runtime edits never write back to them.

The [rework checklist](agent-rework-in-progress.md) records completed removals,
validation and the final history review.
