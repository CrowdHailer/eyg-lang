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

A chat records the messages sent with each completion and the completion, not the request.
The request holds the llm's credentials and the whole chat so far, the messages are only the ones added since the last completion.
The chat for a new message is rebuilt from these events, so it is never replayed.
A completion that was asked for but not recorded is asked for again, it costs a request but has no effect outside the session.
Completions are streamed to show their text as it arrives, only the whole completion is recorded.
If the process stops part way through, the text so far is lost and the completion is asked for again from the start.
The llm is recorded by name, a chat turn can only be replayed while an llm is configured under that name.

The changes made by a tool call that fails are kept, the llm is told it failed and can carry on.
A change that is rejected when it is merged is discarded and the rejection is recorded as the answer to the stop that merged it.
Code fails with it. In a chat the llm is told before the next completion and can repair the change, three times at most.
A rejection before a request or sleep inside a tool call fails that tool call, its result tells the llm.
A chat turn that fails is followed in the next message's chat by a message saying why.

A program built in a structural editor is recorded as its tree in DAG-JSON, not as text.
There is no printer from a tree to EYG text, and some trees, such as binary literals, have no text syntax.
