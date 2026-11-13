---
name: Cloud databases and dataclips
description: Why dataclips run in the caller's process, why databases are named files, and why everything denies raw SQL with a field.
date: 2026-11-12
---

- **Same effects as the CLI.** The cloud implements the roadmap's `SQLite` and `SQLiteQuery` effects from `touch_grass` instead of a cloud only query effect,
  so programs and policies move between Loam and the cloud. `cloud/database.resolve` is Loam's resolution run synchronously with sqlight on one connection.
- **Named databases, not paths.** A database name maps to `<data>/databases/<name>.sqlite`. Gates compare names, and a program cannot point SQLite at the secrets file.
  Many small databases, one per purpose, rather than one workspace database: access is granted per database, and a database is deleted or moved as a file.
- **Dataclips run in the calling process.** A dataclip's `clip` is an EYG closure from the configuration, which must not cross processes
  (see `cloud-process-boundaries.md`). The host's `dataclip` loads the configuration in the caller's process and runs the clip there.
  The cost is evaluating `workspace.eyg` per call, as triggers and turns already do.
- **Raw SQL is a denying field in `shell.everything`.** EYG record spread only overwrites existing fields, so `with_databases(names, shell)` needs `sqlite` to exist.
  `everything` has `sqlite` and `sqlite_query` gates that answer with an error, rather than leaving them out.
- **Dataclips cannot call dataclips.** It avoids loops and keeps a dataclip's reach equal to its own shell.
