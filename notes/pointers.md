---
name: Pointers
description: How shells and boxes compare.
date: 2026-11-23
---

A shell's history is its journal, a sequence of entries that is only appended to.
A file system root is an immutable DAG of blocks and a box is a pointer to a root, its events are where the pointer has been.

| Shell | Box |
| --- | --- |
| journal entry | box event |
| shell id | box id |

A named box is like a branch, a shared pointer that anyone can find by its name.
A box without a name is transient, only something that holds its id can reach it, as a shell is only reached by its id.
Every shell points at a box by id, whether that box has a name says if the shell works on shared files or its own copy.

They move differently.
A shell's journal only grows at its end, one process appends to it so it never conflicts.
A box's pointer moves to a merge of a change and its latest root, which can conflict and must type check.

Transient boxes record nothing about where they were cloned from, a shell in one records the box events it started from.
Boxes and shells are never deleted.
