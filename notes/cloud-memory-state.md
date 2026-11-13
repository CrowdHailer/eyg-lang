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

Rework checklist:

- [x] Audit cloud writes and identify their introducing commits.
- [ ] Remove service feeds/webhooks `97b366d4` and their consumers.
- [ ] Remove EYG cloud helpers/example workspace `fcba3557` and their consumers.
- [ ] Move example-chat/WhatsApp adapters after deployment with their wiring.
- [x] Remove operator pages and quick-trigger UI `e34ae26c` and their routes.
- [ ] Drop secret/snapshot commits and cloud SQLite/dataclip features.
- [ ] Remove runtime and deployment disk-storage wiring.
- [ ] Verify session isolation, mutable settings and deployment without host writes.
- [ ] Review every remaining commit and update the walkthrough before publishing.
