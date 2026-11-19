---
name: Pointers
description: Sessions and boxes are both mutable pointers into immutable DAGs, and what differs between them.
date: 2026-11-19
---

A thread is an append only DAG of events and a session is a pointer to one of its nodes.
A file system root is an immutable DAG of blocks and a box is a pointer to a root, its events are where the pointer has been.
In both the content is identified by its hash and only the pointer changes.

| Thread | File system |
| --- | --- |
| node key | root CID |
| session | box |
| fork a session | clone a box |
| session id | box id |

A named box is like a branch, a shared pointer that anyone can find by its name.
A box without a name is transient, only something that holds its id can reach it, as a session is only reached by its id.
Every session points at a box by id, whether that box has a name says if the session works on shared files or its own copy.

They move differently.
A session's pointer only moves to a child of its head, one process appends to it so it never conflicts.
A box's pointer moves to a merge of a change and its latest root, which can conflict and must type check.

Transient boxes record nothing about where they were cloned from, a session in one keeps the root it started from in its events.
A box is kept in memory until a session is made in it, so a box no session uses, transient or named, is lost when the service stops.
Once a box is durable it is never deleted, as thread nodes are not.

## Transient boxes or a file system reference

A session that does not share files could keep its own root, the latest root in its events, instead of a transient box.
This was looked at and is not simpler, so sessions keep a box.

- Every session moves its files the same way, recorded then merged by its box. A session with its own root needs a second way in
  each place that reads or moves a session's files: starting a segment, settling its change, recovering, the files and artifacts
  of the web interface and the API.
- The box checks a change against an index of its modules kept in its process. A session with its own root needs that index and check too.
- A transient copy takes a copy of its box's secrets, a session with its own root needs somewhere to keep them.
- The box records which changes it merged, so merging again after a restart does nothing. Without a box the events would record it.

What a transient box costs, once a session is made in it, is a row, an event for each change and a process that stays running once it is used.
The processes are the real cost and every box and session has it: the registry never stops a process, stopping idle ones fixes both.

One difference is a choice rather than a cost. A fork of a session in a transient box shares the box, so the two merge their changes.
With their own roots they would diverge, as forked threads do. If forks should diverge, fork into a clone of the box.

