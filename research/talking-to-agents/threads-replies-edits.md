# Threads, replies and edits

A second pass over the six projects for the three things that most often break a
simple "message in, response out" model. Each section compares the projects and then
says what the [glossary](glossary.md) needs.

## 1. Threads

### What the platforms do

| Platform | Thread mechanism | Notes |
|---|---|---|
| Slack | `thread_ts` = root message ts | Thread replies are hidden from the channel unless broadcast. DMs can have threads; Agent View makes every top-level DM message a root. |
| Discord | A thread is a child *channel* with its own id | Forum channels: every post is a thread. Bots can create threads. |
| WhatsApp | none | Only inline replies (quotes). Communities have sub-groups, not threads. |
| Telegram | Forum *topics* in supergroups | Persistent and named; closer to a sub-room than a thread. |
| GitHub | Issue/PR conversation is flat; PR review comments form threads | Review threads can be **resolved**. |
| Email | Thread by `In-Reply-To`/`References` (and subject heuristics) | A tree, not a list: replies can branch. |

### What the projects do

| Concern | OpenClaw | Hermes | nanobot | NanoClaw | Chat SDK | ElizaOS |
|---|---|---|---|---|---|---|
| Session per thread | yes (`:thread:` suffix) | yes, *shared* by all participants | Slack/Discord yes (key override) | `per-thread` session mode | the Thread is the unit | thread is its own Room |
| Thread inherits parent config | binding "parent peer" match, `thread.inheritParent` | `parent_chat_id` | — | per-wiring thread policy | — | — |
| Top-level mention starts a thread | seeds the root into the thread session it will create | Discord auto-thread (default on); Slack replies in thread | `reply_in_thread` opens one | adapter-dependent | app code | — |
| Follow-ups without mention | `implicitMentions.threadParticipation` | wake checks: bot posted root, thread was mentioned, active session, parent mentions bot | no | `mention-sticky` | `subscribe()` | `MentionContext.isThread` |
| Seeding history | fetch root + up to 20 thread messages on first turn | backfill since last reply | prepend thread context on first mention | — | `thread.allMessages` | providers read room memories |
| Multi-bot threads | bot-pair loop protection | `thread_require_mention`, continuation window | — | per-wiring engage | — | — |

### Findings

1. **"Thread" names three different things.** A Slack thread (anchored on a root, hidden
   from the room), a Discord thread (a child room), a Telegram topic (a persistent named
   sub-room). The glossary keeps one word, Thread, defined by its *anchor* (a root
   message) and allows a Thread to be a Room in its own right where the platform makes it so.
2. **Entering a thread is an engagement event.** Every project that handles threads well
   remembers that the agent was addressed in a thread and keeps listening there. That is
   the **Subscription** concept, and it should be explicit state, not inferred from
   caches (Hermes re-derives it after restart by fetching the parent; OpenClaw by reading
   Slack; Chat SDK stores it in the state adapter).
3. **Placement is a decision, not a property of the platform.** Whether a response goes
   inline, into the trigger's thread, or into a new thread is per-binding policy
   (OpenClaw `replyToMode`, Hermes auto-thread, nanobot `reply_in_thread`). When the
   agent opens a new thread with its response, the session must be keyed on the thread
   it is about to create (OpenClaw "seeding", Hermes `prospective_thread_id`) so the
   next message from the user lands in the same session. The glossary names this
   **Placement: Threaded**.
4. **Sharing a thread across people** is the normal case. Hermes isolates *groups* per
   participant by default but shares *threads*; OpenClaw shares both. A thread is a
   multi-author conversation and every Input needs its author rendered (OpenClaw sender
   labels, Hermes `[sender name]` prefixes).
5. **Thread state exists on some platforms**: resolved (GitHub review threads), archived
   or locked (Discord), closed (Linear agent session). Resolution is a natural end of a
   Subscription.

## 2. Replies (`replies_to`)

### What the projects do

| Concern | OpenClaw | Hermes | nanobot | NanoClaw | Chat SDK | ElizaOS |
|---|---|---|---|---|---|---|
| Parent hydrated as context | `ReplyToBody`, `ReplyToSender`, full `ReplyChain`, `[Replying to ...]` block | `reply_to_text`, author; WhatsApp attaches quoted media | metadata only | in serialized Chat SDK message | `Message` (platform raw) | `content.inReplyTo` (memory id) |
| Reply to the agent counts as addressing | yes (`implicitMentions.replyToBot`, WhatsApp mention rule) | yes (`reply_to_is_own_message`) | WhatsApp `is_reply_to_bot` | — | — | `MentionContext.isReply` |
| Quoted bot text admits a turn alone | no: "quoted bot text is context for the current message" | — | — | — | — | — |
| Outbound response quotes trigger | `replyToMode`, `[[reply_to:<id>]]` tags | reply anchor = trigger (or redirect target) | `reply_to` = message_id | routing copied from input | `thread.post` | `reply_to: memory.id` |
| Forwarded messages | `ForwardedFrom*` fields | — | — | — | — | — |

### Findings

1. **Reply and thread are different relations and both are needed.** A WhatsApp reply
   points at one message and stays in the room; a Slack thread is a place. Email's
   `In-Reply-To` is both: it points at a message *and* defines the thread. The glossary
   uses `replies_to` for the relation and Thread for the place, and lets an Integration
   derive one from the other where the platform conflates them.
2. **A reply is an addressing signal, a quote is content.** Replying to the agent's
   message engages the agent; the quoted text itself is **Content** provenance and must
   not be treated as an instruction (OpenClaw is explicit about this).
3. **Which message a response answers can change mid-turn.** When an Input steers or
   redirects a running Turn, the response should quote the *latest* addressed message,
   not the first (Hermes `reply_anchor_override`, OpenClaw "a final source reply completes
   only the input it answers"). The Turn therefore tracks **which Requests it answers**,
   not one trigger.
4. **Self-replies.** On Personal accounts (OpenClaw WhatsApp) a reply to "my" message may
   be a reply to the human owner, not the agent. Receipts (the ids the agent actually
   sent) are the only reliable way to know a message was the agent's.

## 3. Edits

### Inbound edits (a participant edits their message)

| Project | Policy |
|---|---|
| OpenClaw | Slack: edits/deletes become **system events** in the routed session (a Notice). Telegram: an edit of a still-pending message **supersedes** it. Transcripts are never rewritten. |
| Hermes | Slack `message_changed`: if the original was never routed, the edit is **re-evaluated as a new message** (the user edited in the @mention); if it was routed, the edit is dropped. Telegram edits carry an `edit_revision` so admission can tell them apart from the original. |
| nanobot | **Ignored** (`message_changed` filtered with all other subtypes). |
| NanoClaw | **Ignored** inbound. |
| Chat SDK | Separate **lifecycle handler** `onMessageUpdated(thread, message, previous)`, outside routing and concurrency; only the Slack adapter emits it today. |
| ElizaOS | Discord: an edit **cancels** a turn that has not started typing ("superseded by an edit") and **re-runs** with the new revision; a visible turn finishes first; only newer revisions count; bot edits ignored. |

These are not competing designs; each is right for one *state* of the edited message.
Combined into one policy keyed on that state:

| State of the original message | Edit should |
|---|---|
| Not admitted, or Ignored by Engagement | **Re-evaluate** the new revision (it may now mention the agent) |
| Observation already recorded | Record a **Notice** (`edited: "old" -> "new"`) |
| Request pending (coalescing window or queued) | **Supersede**: replace the Input |
| Request in a running Turn, nothing visible yet | **Supersede**: cancel the Turn and restart |
| Request in a running Turn with visible output | Let the Turn finish, then deliver a **Notice** so the next Turn sees the change (or Steer it in) |
| Request already answered | **Notice**; optionally a new Request if the edit was addressed |

The session transcript stays **append-only**: an edit adds a Revision event rather than
rewriting history, which keeps prompt caches valid and makes the change visible to the
model ("Alice edited her message: ..."). Every project that keeps transcripts does this.

### Deletions

OpenClaw records a Notice; Chat SDK exposes `onMessageDeleted` (best-effort previous
message); the others ignore deletions. None of the projects removes deleted content from
the agent's transcript or long-term memory. The language needs an explicit choice per
binding: **Note** (record that it was deleted) or **Forget** (remove from transcript and
memory where possible). Deletion is also the user's main "undo" for a message sent to
the wrong place, so Supersession should apply to pending Requests.

### Outbound edits (the agent edits its own messages)

1. **Drafts.** All projects stream by posting once and editing (Discord, Slack,
   Telegram); Slack native streams and Hermes' "stream-is-the-message" contract require
   drafts to be prefix-stable and **sealed** exactly once. Email and WhatsApp Cloud cannot
   edit, so the Response is buffered.
2. **Echo suppression.** Platforms report the bot's own edits back as edit events. Chat
   SDK and ElizaOS filter bot-authored edits; Hermes tracks processed timestamps.
   Without this, streaming produces one inbound edit per delta.
3. **Agent-initiated edits** (correcting an earlier answer) are an Action on a
   **Receipt** (NanoClaw `edit` operation with a message id the agent saw in its context).
   This requires Receipts to be stored and the message ids to be visible to the model.
4. **Progress cards and status reactions** are edits too: OpenClaw and Hermes update a
   single progress message or reaction in place through the turn.

## 4. Changes made to the glossary from this review

- Thread is defined by its **root anchor**, and may be a Room in its own right.
- **Subscription** is explicit, persisted state with explicit endings (unsubscribe,
  resolution, expiry).
- **Placement** includes *Threaded* with prospective thread keying.
- `replies_to` is a relation on Message; "reply" is not a noun.
- A Turn answers a **set of Requests**, so the response anchor can move.
- Messages carry **Revisions**; Edit and Deletion have state-dependent policies:
  Re-evaluate, Notice, Supersede, Note/Forget.
- Transcripts are append-only.
- Outbound: **Draft** + **Seal**, **Receipt**, echo suppression as an Integration duty.
