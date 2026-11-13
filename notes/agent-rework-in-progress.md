---
name: Agent branch rework checklist
description: Requested removals, moves and final history review for the in-memory cloud revision.
date: 2026-11-13
---

Base: main `ea52e422`. Published starting point: bot agent `abb3cf16`.
Delivery target: bot `agent`. Final history: 62 commits including review; deployment
is commit 3.

- [x] Remove local secret store `bb22e74a` and snapshots `02907612`.
- [x] Audit all cloud persistence: remove cloud SQLite/dataclips `23718651` and dependent guides/recordings `f0aa7cac`.
- [x] Remove session save callbacks, storage paths, user JSON, source-file writes and data-volume initialization from retained runtime/deployment commits.
- [x] Keep session roots/history, users, source edits, secrets and artifacts in memory. Document that cluster replication/recovery remains separate work.
- [x] Remove service feeds/webhooks `97b366d4`, event logs, consumers and examples. Keep only shared event types and chat webhook plumbing needed by retained adapters.
- [x] Remove public EYG cloud helpers and example workspace `fcba3557`; use small runtime test fixtures.
- [x] Remove operator pages/quick-trigger UI `e34ae26c`, their routes and checks.
- [x] Move example-chat/WhatsApp implementations and wiring after deployment; keep the standalone chat app separate.
- [x] Keep network secrets immediately after deployment, independently packaged and tested.
- [x] Preserve main's serial actor, direct replies, fresh scope, Clockwork and startup triggers; agents remain unbounded.
- [x] Preserve earlier source-checking simplification, reserved keyword fields, Pass/Mock policy, OTel folding and removal of hub artifact storage.
- [x] Validate deployment: 110 cloud / 87 EYG tests, Docker read-only boot, HTTP 200 / 401 and no filesystem changes.
- [x] Validate later stages: 120 chat-adapter tests; 138 native/final cloud tests, 198 CLI tests and 260 repository EYG tests.
- [x] Final step: review every commit, fold dependency fixes at first use, simplify obsolete design guidance and update the ten-slide HTML/PDF.

See [every commit's disposition](agent-commit-review.md) and
[the deployment boundary](agent-predeployment-review.md). No production deployment
or merge into main is claimed.
