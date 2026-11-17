---
name: Session events
description: Trade-offs in what a session records to be resumed.
date: 2026-11-17
---

How a turn is recorded and replayed is described in `packages/cloud/src/cloud/sessions/turn.gleam`.

Secrets are never recorded, each secret a turn reads is recorded as a fingerprint.
A fingerprint is a short hash of the name and value, without a key so it still matches after a session is exported and imported.
A weak secret could be guessed from its fingerprint, and a turn that returns or prints a secret records it in its outcome.

A request without a recorded response is sent again only if it is GET or HEAD.
Any other request is answered with a network error, so it is sent at most once.
A sleep that was stopped is started again from the beginning.

The events of a segment are recorded together, before its change is merged into the box.
A segment whose events were never recorded runs again with new answers, nothing it did was kept.

A change is identified by the key of its segment's last event in the thread, the box records it and merges a change only once.
Resuming a session merges its last change again, which does nothing if it was merged, even if those files changed since.
Keys come from the history, so a fork or a copy made from exported events identifies the change the same way.

The module each package reference resolves to is recorded and used again when the turn is replayed.
A turn resolves a package once, later releases are seen by the next turn.

The returned and finished events record the value and output of a turn although replay could compute them,
so turns can be listed without running any code. Finished is recorded once the change is merged or rejected.

Events are recorded at the time they are inserted, not when their transaction started.
Events recorded together are close in time, so a trace shows them in order.
