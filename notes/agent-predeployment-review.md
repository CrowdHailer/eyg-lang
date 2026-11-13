---
name: Agent deployment boundary review
description: Three commits to a cloud deployment with in-memory state and no writable host storage.
date: 2026-11-13
---

Base: main `ea52e422`, including its Clockwork scheduler. Main's serial actor,
private roots, fresh execution scope, direct replies and native startup triggers
remain. Cloud state stays in memory; cluster replication is not implemented here.

| Stage | Commit | Review |
| --- | --- | --- |
| Runtime | `b43673ce` | Source checks, actor-held settings/users/secrets, private session roots/history, shell/API, triggers, Clockwork and initial tracing. No host stores, feeds, public cloud helpers or operator pages. |
| Guidance | `e25dac4e` | Retain only current API, web-shell and tracing workflows. |
| Deployment | `7f639db8` | Ship startup inputs in the image. No data-directory initialization or writable volume. |

Verified deployment checkpoint: strict cloud build, 110 cloud tests, 87 EYG tests
with its checkout-built CLI, Docker build and read-only boot. `/` returns 200;
unauthenticated `/api/me` returns 401. Docker reports no filesystem changes.

Network secrets are the next commit, as an independent policy package. The
example-chat/WhatsApp implementations and wiring, standalone chat application,
and native adapter extensions follow. Main's basic adapters remain available
before that boundary. Queries and broad local dependencies land later; cloud
SQLite/dataclips and their documentation are removed entirely.

Startup configuration/imports/seeds are read-only inputs. Source edits and secrets
are mutable actor data, not files. Fresh owners do not restore local snapshots.
The [deployment guide](../packages/cloud/deploy/README.md) retains the example-login
limitation. See [the full review](agent-commit-review.md) for every later commit.
