---
name: Box changes
description: Trade-offs in how a box moves to a new file system root.
date: 2026-11-17
---

Changes are made away from the box, from a base root, and sent to the box's one process.
The process merges each change onto the latest root, rejects it if a path was changed on both sides,
type checks the result and records it. Changes are never retried.

Reads are not tracked, as on a normal file system reading then writing is not transactional.
A change whose files did not conflict is accepted even if files it read changed since its base.
Nothing promises that a long running change sees the latest files, it sees its base.

Changes are visible as soon as they are merged.
In progress work is meant to be hidden by working in a transient box and merging it when done.

The whole file system is type checked from fresh on every change.
This reads every directory and `.eyg` file from the blob store, memoising on the previous root is the planned improvement.

A session turn that fails discards its file changes, even those made before the failure.
This differs from the chat sessions in `cloud/session.gleam` which keep them.
Keeping the change atomic means a turn can write several modules that depend on each other.

Blocks are put in the blob store as they are written, before the change is checked or recorded.
A change that is rejected leaves blocks in the store that no root references, they are harmless as blocks are content addressed.
Nothing is cached so every block read is a request to the store, a cache can sit behind the same interface because blocks never change.
