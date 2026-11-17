---
name: Threads
description: Trade-offs in storing history as an append only DAG with sessions as pointers.
date: 2026-11-17
---

Events are stored as nodes of an append only DAG, see `packages/cloud/src/cloud/data/thread.gleam`.
A node's key is a hash of its parent's key and the event, so a key identifies the whole history up to the event.
A session is a pointer to the last node of its history.

Identical histories are one history, appending an event that is already in the thread adds nothing.
Importing an exported session reuses the nodes that are already in the thread.
The key of a segment's last event identifies its change to a box, so every session at that position merges it once.

Two sessions that never shared a history but record identical events also share nodes and change keys.
For example two new sessions running the same code from the same root, with the same answers.
They are indistinguishable, so the second's change is treated as already merged.
If that is ever unwanted a session can start its history with an event that is unique to it.

Nodes are never deleted. Nodes that no pointer reaches are kept, there is no collection yet.

A node records the time it was first appended, a shared node shows when the first history reached it.
An import keeps the exported times only for nodes that were not already in the thread.

Reading a history follows parent keys from the head, it costs one recursive query and grows with the length of the history.
Payloads are stored as text rather than JSONB, so the stored bytes are the bytes that were hashed.
Changing how an event is encoded changes its key, old nodes keep their keys and new events start new branches.
