---
name: Box changes
description: Trade-offs in how a box moves to a new file system root.
date: 2026-11-16
---

A change to a box is made against the root it was read at and recorded as the next event in sequence.
If another change was recorded first the later one fails with a conflict, nothing is merged.
A three way merge of the file systems is the planned replacement.

The whole file system is type checked from fresh on every change.
This reads every directory and `.eyg` file from the blob store, memoising on the previous root is the planned improvement.

A session turn that fails discards its file changes, even those made before the failure.
This differs from the chat sessions in `cloud/session.gleam` which keep them.
Keeping the change atomic means a turn can write several modules that depend on each other.

Blocks are put in the blob store as they are written, before the change is checked or recorded.
A change that is rejected or conflicts leaves blocks in the store that no root references, they are harmless as blocks are content addressed.
Nothing is cached so every block read is a request to the store, a cache can sit behind the same interface because blocks never change.
