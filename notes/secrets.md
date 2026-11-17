---
name: Secrets
description: Trade-offs in keeping secrets in each box.
date: 2026-11-17
---

Each box has its own secrets, code in the box reads them with the `Env` effect.
Sessions in a box do not see the secrets the service was started with, only those of the box.

A clone gets a copy of the secrets, like it gets the root, so a transient copy can do what the box can.
Changing a secret in a box does not change its clones.

Values are stored as they are in Postgres, they are not encrypted.
Values are never returned by the API or shown in the terminal interface, only names are.
