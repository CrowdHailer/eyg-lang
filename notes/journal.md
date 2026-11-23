---
name: Shell journal
description: Trade-offs in what a shell records to be resumed.
date: 2026-11-23
---

How a turn is recorded and replayed is described in `packages/cloud/src/cloud/shells/turn.gleam`.

The journal is keyed by shell and sequence, entries are only appended.
Two processes cannot both continue a shell, the second append fails on the key.
A fork copies the journal rather than sharing it, histories are small and a copy needs no pointers.

An input records the box event its segment starts from, not the root.
A shell never moves between boxes, so the sequence is enough and the journal links to the box's history.
The root is looked up from the latest box event at or before it that has a root, so box events that only rename keep working.
An output does not record the box event it made, the box event is written in the same transaction.

An output and the box event of its change are written in one transaction, by the box's process.
Either both are recorded or neither is, so a change is never merged twice and there is nothing to merge again after a restart.
When the box rejects a change that the code is waiting on, the output and the input that answers with the rejection are one transaction.

Secrets are never recorded, each secret a turn reads is recorded as a fingerprint.
A fingerprint is a short hash of the name and value, a weak secret could be guessed from it,
and a turn that returns or prints a secret records it in its outcome.

A request without a recorded response is sent again only if it is GET or HEAD.
Any other request is answered with a network error, so it is sent at most once.
A sleep that was stopped is started again from the beginning.
A segment whose output was never recorded runs again from its input with new answers, nothing it did was kept.

The module each package reference resolves to is recorded and used again when the turn is replayed.
A turn resolves a package once, later releases are seen by the next turn.

The finished output records the value and output of a turn although replay could compute them,
so turns can be listed without running any code.

Entries are recorded at the time they are inserted, not when their transaction started, so a trace shows them in order.

The changes made by code that fails are not kept.
A change that is rejected when it is merged is discarded and the rejection is the answer to the stop that merged it, code fails with it.

A program built in a structural editor is recorded as its tree in DAG-JSON, not as text.
There is no printer from a tree to EYG text, and some trees, such as binary literals, have no text syntax.
