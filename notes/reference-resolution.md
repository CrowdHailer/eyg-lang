---
name: reference resolution
description: File imports, releases and content references are found during checking rather than execution.
date: 2026-10-29
---

All references should be found during checking.
Execution support should consume the dependencies prepared by that process,
rather than introduce a second file-loading path when evaluation encounters an unresolved reference.

Checking prepares both types and runtime values for file imports.