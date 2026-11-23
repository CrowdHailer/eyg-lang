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

Changes are visible as soon as they are merged, for a shell that is at each request or sleep.
In progress work is meant to be hidden by working in a transient box and merging it when done.

The box process keeps the `unixfs/check` index of the modules at its root.
A change only checks the modules that changed, or failed, and every module that imports them.
The index is only in memory, so the first change after the box process starts checks every module.

Code that fails discards the changes made since its last request or sleep, even those made before the failure.
This differs from the Slack sessions in `cloud/session.gleam` which keep them.
Keeping the change atomic means code can write several modules that depend on each other, as long as it makes no request in between.

Blocks are put in the blob store as they are written, before the change is merged or recorded.
A change that is rejected leaves blocks in the store that no root references, they are harmless as blocks are content addressed.
Nothing is cached so every block read is a request to the store, a cache can sit behind the same interface because blocks never change.
