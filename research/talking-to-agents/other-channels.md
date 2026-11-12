# Other channels: GitHub issues and email

Does the [glossary](glossary.md) still work when the front end is a GitHub issue or an
email inbox instead of a chat app? Evidence comes from the reviewed projects that already
support these channels:

- Chat SDK: GitHub, GitLab, Linear, Notion and Gmail adapters; `message.subject`.
- Hermes: email adapter (IMAP/SMTP), webhook routes with `deliver: github_comment`,
  per-entity coalescing.
- nanobot: email channel, Linear agent-session channel.
- NanoClaw: GitHub and Linear through Chat SDK; "shared session" isolation level built
  around pairing GitHub webhooks with a Slack channel.

## GitHub issues and pull requests

### Mapping

| Glossary | GitHub |
|---|---|
| Platform | GitHub |
| Account | a GitHub App installation or a bot user |
| Realm | organisation / user account |
| Room | repository (kind Channel; Audience Public or Members) |
| Thread | an issue or PR conversation (root = the issue body); a PR review-comment thread is a Thread inside it |
| Subject | the issue or PR itself: title, state (open/closed/merged/draft), labels, assignees, linked branch |
| Message | issue body, comment, review, review comment |
| Mention | `@app-name` |
| replies_to | quote-reply (weak, text only); review comment replies (strong) |
| Revision / Edit | comment edits are common; **issue-body edits change the Subject's request** |
| Reaction | 👍 👀 🎉 ... |
| Membership | collaborators, team membership; issue participants |
| Admission | repository permission (read / triage / write / admin), org membership |
| Command | `/command` comments are a convention, not a platform feature |
| Indicator | no typing; a 👀 reaction is the usual acknowledgement; a "working on it" comment edited in place acts as a status card |
| Draft | possible (comments are editable) but each *new* comment notifies watchers, so stream by editing one comment |
| Action | label, assign, close, request review, open PR, push commit, resolve thread |

### Fits well

- **Conversation / Thread / Subject.** An issue is a Thread with a Subject. This matches
  Chat SDK's ids (`github:owner/repo:issue:42`) and its `subject` concept. Session scope
  **per Thread** is the natural default (one session per issue).
- **Engagement.** Mention, Sticky (once mentioned on an issue, follow-ups in that issue
  are for the agent), Pattern (label names) all apply unchanged.
- **Busy policy and Coalescing.** Webhook bursts (several pushes, edits, labels) must be
  coalesced per Subject (Hermes `coalesce.key: pull_request.number`).
- **Provenance.** Issue bodies and comments from non-collaborators are Content from
  Strangers on a public Room: exactly the prompt-injection case the Provenance term
  exists for.

### What the chat vocabulary lacks

1. **Assignment as an addressing signal.** On GitHub (and Linear, Jira) the strongest way
   to address the agent is not a mention but *assigning* the issue, *requesting a
   review*, or *adding a label*. These are Subject events, not Messages. Engagement needs
   **addressing by Subject change**, and the Disposition of such an event is a Request.
   Linear goes furthest: delegating an issue to an agent creates a platform-side
   **agent session** (nanobot uses its id as the Conversation id).
2. **Subject events.** Title edits, state changes (closed, reopened, merged), label and
   assignee changes, CI results. These become Notices, Requests (assignment) or end a
   Subscription (closed, merged, thread resolved).
3. **Output is mostly Actions.** A useful agent answers an issue with a branch and a PR,
   not a comment. The Response is often a short comment that *links* to the Action's
   result. The Output type needs `Act` as a first-class citizen, which the glossary has.
4. **Edits to the root are edits to the request.** Editing the issue body re-specifies
   the work; under the edit policy table this is "Request already answered → Notice and
   possibly new Request".
5. **Resolved threads.** Review threads have a resolved/unresolved state that both humans
   and the agent change. Resolution ends the Subscription for that thread.
6. **Latency expectations differ.** Nobody expects a typing indicator; minutes are fine;
   one consolidated comment is better than many. Placement and Draft policy should be
   driven by Capability *and* convention.

## Email

### Mapping

| Glossary | Email |
|---|---|
| Platform | email (IMAP/SMTP, Gmail API, JMAP) |
| Account | a mailbox address (possibly an alias or a label-filtered view) |
| Realm | none useful (the domain is not an administrative boundary for recipients) |
| Room | **none**: there is no persistent room; a Thread stands alone |
| Thread | the reply tree defined by `Message-ID` / `In-Reply-To` / `References` |
| Subject | the subject line is the Subject's title; the Subject is usually implicit (a request, a booking, a ticket) |
| Message | one email |
| replies_to | `In-Reply-To` (and it defines the Thread) |
| Audience | **To / Cc / Bcc**, and always Unknown overall (forwarding) |
| Mention | the agent's address in **To** (addressed) vs **Cc** (observing); name in the body |
| Revision / Edit | none; corrections arrive as new messages ("sorry, I meant Tuesday") |
| Deletion | none visible to the agent |
| Reaction | none (Outlook/Gmail reactions are new messages in practice) |
| Indicator | none; an auto-acknowledgement email is the only option and is usually unwanted |
| Draft | not possible: sent email cannot be edited or retracted; buffer and send once; optionally create a *mailbox draft* for human review |
| Admission | sender allowlist **plus authentication** (DMARC / SPF / DKIM alignment) because `From:` is forgeable |
| Placement | reply to sender vs reply-all vs a private reply in the same thread |

### Fits well

- **Thread, replies_to, Message, Request, Response.** The core loop is the same: an
  addressed email is a Request, the Response goes back into the Thread with correct
  `In-Reply-To` / `References` and `Re:` subject (Hermes, nanobot, Chat SDK Gmail).
- **To vs Cc maps onto Request vs Observation.** Being in To means a response is owed;
  being in Cc means the agent is informed and may stay silent. This is a better
  addressing signal than mention parsing.
- **Coalescing.** Several emails in the same thread arriving within one sync are one
  Turn (Chat SDK Gmail coalesces to the newest).
- **Provenance.** Forwarded mail, quoted history and attachments are Content.

### What the chat vocabulary lacks

1. **Rooms are optional.** Email (and SMS-style 1:1 channels) has threads with
   per-thread audiences and no room. The glossary therefore makes `room: Option(Room)`
   and lets Audience be computed per Message. "Direct" is not a room kind here but an
   Audience (one recipient), and even that can change mid-thread when someone adds a Cc.
2. **Audience selection is part of Placement.** Reply-to-sender, reply-all, and private
   reply in the same thread (Chat SDK's ephemeral fallback) are different Placements
   with different leak risks. The agent must not carry content from a private branch
   into a reply-all (Chat SDK warns about this explicitly).
3. **Threads are trees.** Two people can reply to the same message, creating branches.
   Session scope *per Thread* still works, but the transcript must keep the
   `replies_to` structure or the model will interleave branches.
4. **Session key must not be the sender.** Hermes and nanobot key email sessions on the
   `From:` address, so two unrelated threads with the same person share context and one
   thread with three people splits into three sessions. Per-Thread scoping (by root
   `Message-ID`) matches the glossary and Chat SDK.
5. **Identity is weak.** Admission needs an authentication result, not just an address.
   The glossary's Provenance carries identity strength; email is the case that forces
   it.
6. **No edits means no Supersession, but corrections still happen.** A correction is a
   new Message in the Thread; Coalescing (a quiet window per thread) covers the common
   "oops, one more thing" pattern that Supersession covers on chat.
7. **Slow and asynchronous.** No Indicators; Busy policy is effectively Queue or Collect;
   a long-running Turn may want to send an interim "I'm on it" only when the work will
   take hours.

## Verdict

The vocabulary holds: Platform, Account, Conversation, Thread, Message, `replies_to`,
Participant, Admission, Engagement, Disposition (Request / Observation), Subscription,
Session and Session scope, Turn, Busy policy, Coalescing, Response, Post, Placement,
Action and Provenance all carry over to GitHub and email with the same meaning.

What chat-first designs under-specify, and these channels force into the language:

| Addition | Forced by | Status in glossary |
|---|---|---|
| **Subject** with state (title, open/closed, assignees, labels) | GitHub, Linear, email subject | added |
| **Subject events** as addressing signals (assign, request review, label) | GitHub, Linear | added under Engagement as "addressing by Subject change" (see above) |
| **Room is optional**; Thread can stand alone | email | added |
| **Audience** separate from Room kind, including To / Cc and Unknown | email, public repos | added |
| **Capability-driven Draft** (buffer when edits are impossible or noisy) | email, GitHub notifications | added |
| **Action** as a first-class output | GitHub | added |
| **Thread resolution** ending a Subscription | GitHub review threads, Linear sessions | added |
| **Identity strength** in Provenance | email `From:` | added |
| **Tree-shaped threads** | email | noted; transcripts keep `replies_to` |

Linear's agent API is a useful check from the other direction: the platform itself
already models an **agent session** with **activities** (thought, action, elicitation,
response, error). Those line up with Turn, Indicator/Status, Ask and Response in this
glossary, which suggests the vocabulary is close to what platforms are converging on.
