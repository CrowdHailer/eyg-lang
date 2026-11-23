---
name: Pointers
description: How shells and boxes compare, and why a shell keeps a box rather than its own root.
date: 2026-11-23
---

A shell's history is its journal, a sequence of entries that is only appended to.
A file system root is an immutable DAG of blocks and a box is a pointer to a root, its events are where the pointer has been.

| Shell | Box |
| --- | --- |
| journal entry | box event |
| fork a shell | clone a box |
| shell id | box id |

A named box is like a branch, a shared pointer that anyone can find by its name.
A box without a name is transient, only something that holds its id can reach it, as a shell is only reached by its id.
Every shell points at a box by id, whether that box has a name says if the shell works on shared files or its own copy.

They move differently.
A shell's journal only grows at its end, one process appends to it so it never conflicts.
A box's pointer moves to a merge of a change and its latest root, which can conflict and must type check.

Transient boxes record nothing about where they were cloned from, a shell in one records the box events it started from.
Boxes and shells are never deleted.

## Transient boxes or a file system reference

A shell that does not share files could keep its own root, the latest root in its journal, instead of a transient box.
This was looked at and is not simpler, so shells keep a box.

- Every shell moves its files the same way, recorded then merged by its box. A shell with its own root needs a second way in
  each place that reads or moves a shell's files: starting a segment, settling its change, recovering, the files and artifacts
  of the web interface and the API.
- The box checks a change against an index of its modules kept in its process. A shell with its own root needs that index and check too.
- A transient copy takes a copy of its box's secrets, a shell with its own root needs somewhere to keep them.
- The box's process records a change in the same transaction as the shell's output. Without a box the shell would merge and record its own changes.

What a transient box costs is a row, an event for each change and a process that stays running once it is used.
The processes are the real cost and every box and shell has it: the registry never stops a process, stopping idle ones fixes both.

One difference is a choice rather than a cost. A fork of a shell in a transient box shares the box, so the two merge their changes.
With their own roots they would diverge. If forks should diverge, fork into a clone of the box.

