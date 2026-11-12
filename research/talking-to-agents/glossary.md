# Glossary: a language for talking to agents

This glossary proposes one name per concept, chosen after comparing six projects
(see the pipeline files in this directory). Each entry gives the definition, the reason
for the name, and what the reviewed projects call it. The terms are grouped by the
order a message travels: **places and people**, **what happens**, **gates**,
**routing**, **running**, **speaking**.

Rules used when choosing names:

1. **Platform-side and agent-side things get different nouns.** A Slack thread is a
   *Conversation*; what the agent remembers about it is a *Session*. Most confusion in
   the reviewed code comes from one word covering both.
2. **Never reuse a word a platform already uses for something else.** "Channel" means a
   Slack/Discord channel to users, so the integration layer is not called a channel.
   "Workspace" means a Slack workspace *and* an agent's file system, so neither uses it.
3. **One noun per role in a sentence.** The agent *responds* to a *request*; a message
   *replies to* another message. "Reply" is never used as a noun.
4. **Prefer words a non-programmer would guess correctly.**

A Gleam sketch of the whole vocabulary is at the end.

---

## 1. Places and people

### Platform
A messaging service the agent can be reached through: Slack, Discord, WhatsApp,
Telegram, email, GitHub, Linear.
*Why:* "channel" is taken by Slack/Discord; "transport" suggests the wire protocol
(Socket Mode vs webhooks), which is a detail of an integration.
*Others:* OpenClaw `channel`, Hermes `Platform`, nanobot `channel`, NanoClaw `channel_type`,
Chat SDK `adapter`, ElizaOS `source`.

### Integration
The code that connects one Platform to the system: receives platform events, normalises
them, delivers outputs. Has a **Capability** set (below).
*Others:* OpenClaw "channel plugin", Hermes/Chat SDK "adapter", nanobot `BaseChannel`,
NanoClaw "channel adapter", ElizaOS "plugin/service".

### Account
One authenticated identity of the agent on a Platform: a bot user, a phone number, a
mailbox, a GitHub App installation. An Integration may run several Accounts.
Kinds: **Bot** (a dedicated identity) or **Personal** (the agent acts through a human's own
account, as OpenClaw does on WhatsApp; then "messages from me" are ambiguous and echo
suppression matters).
*Others:* OpenClaw `accountId`, Hermes "bot"/`transport_profile`, NanoClaw `instance`.

### Realm
The administrative boundary that owns rooms, members and roles on a platform, inside
which platform ids are unique: Slack workspace, Discord guild, Matrix homeserver, GitHub
organisation or user.
*Why:* "workspace" collides with the agent's workspace, "server" with the gateway,
"world" (ElizaOS) reads as fiction, "guild" and "team" are platform brands.
*Others:* OpenClaw `guildId`/`teamId`, Hermes `scope_id`/`guild_id`, ElizaOS `World`.

### Room
A persistent place with a membership where messages are posted: a DM, a WhatsApp group,
a Slack channel, a Discord channel, a GitHub repository.
**Room kind** describes the membership:
- **Direct**: exactly the agent and one other participant.
- **Group**: a membership-defined, usually unnamed set (WhatsApp group, Slack multi-person DM).
- **Channel**: a named room with open-ended membership (Slack/Discord channel).

Room kind and **Audience** (below) are separate: a channel can be private, an email can be
to one person and still be forwarded.
*Others:* OpenClaw peer + `ChatType` (`direct | group | channel`), Hermes `chat_id` +
`chat_type`, NanoClaw **messaging group**, Chat SDK `Channel`, ElizaOS `Room`.

### Thread
A sub-conversation inside a Room, anchored on a **root** message: Slack thread, Discord
thread, Telegram forum topic, GitHub review-comment thread, email thread. A Thread may
exist **without** a Room (an email thread is its own place).
*Others:* everyone says thread; Telegram says topic; ElizaOS makes threads Rooms of type
`THREAD`; Chat SDK makes every conversation a Thread.

### Conversation
The place a message belongs to and a response goes back to: a Room, a Thread, or a Thread
in a Room. This is the platform-side unit; it is identified by a **Conversation id**
(e.g. `slack:T1:C2:1700000000.1`).
*Why not "chat"?* "Chat" is also the verb and the product category.
*Others:* OpenClaw "route"/`OriginatingTo`, Hermes `SessionSource`, NanoClaw
`platformId + threadId` (`DeliveryAddress`), Chat SDK `Thread`.

### Audience
Who can see a message, as far as the platform tells us: **Private** (only the agent and
the author), **Members** (the room's membership), **Public**, or **Unknown** (email, where
recipients can forward). Needed so the agent does not leak one conversation into another.
*Others:* mostly implicit; Chat SDK reports Gmail visibility as `unknown`.

### Participant
Anyone who posts in a conversation. Kinds: **Person**, **Bot** (another automated
account), **Self** (one of the agent's own Accounts). The author of a Message is a
Participant.
*Others:* OpenClaw `Sender`, Hermes `user_id`, nanobot `sender_id`, NanoClaw `user`,
Chat SDK `Author`, ElizaOS `Entity`.

### Person
A human known to the system, possibly linked to several Participants on different
platforms. Optional: most projects do not link identities across platforms (NanoClaw
says so explicitly).

### Role
What a Person may do: **Owner** (the person the agent works for), **Admin**, **Member**,
**Stranger** (admitted but unknown, e.g. open rooms).
*Others:* OpenClaw owner + allowlists, Hermes admin/allowed users, NanoClaw
`owner | admin | member`.

### Subject
The work item a Conversation is about, with its own state: a GitHub issue or pull
request, a Linear issue, an email's subject line, a support ticket. Chat rooms usually
have none (a channel *topic* is the closest). Has a title, a state (open, closed,
merged), and may have assignees and labels.
*Others:* Chat SDK `message.subject`. See [other channels](other-channels.md).

### Capability
What a Platform supports, declared by the Integration: threads, replies-to, edits,
deletions, reactions, typing indicators, drafts (edit-in-place streaming), cards and
buttons, ephemeral messages, read receipts, message length limit. Every output path
degrades by Capability rather than by platform name.
*Others:* Chat SDK feature matrix, Hermes `CapabilityDescriptor` (relay), NanoClaw
"graceful degradation".

---

## 2. What happens (inbound events)

### Message
A unit of content posted by a Participant in a Conversation. Has an id, author, **Body**,
**Mentions**, optional **replies_to**, a timestamp and a **Revision**.
*Others:* OpenClaw `MsgContext`, Hermes `MessageEvent`, nanobot `InboundMessage`,
NanoClaw `messages_in` row, Chat SDK `Message`, ElizaOS `Memory`.

### Body
The content of a Message: text (as markdown or AST) plus **Attachments** (files, images,
voice, location). Platform rich text (Slack blocks, unfurls, quoted forwards) is folded
into the Body by the Integration.

### Mention
A Message's explicit reference to a Participant (`@agent`). A mention of the agent is the
strongest addressing signal; a mention of someone else is a signal that the message is
*not* for the agent (Hermes `ignore_other_user_mentions`).

### replies_to (relation)
A Message *replies to* another specific Message: WhatsApp/Telegram/Discord reply, email
`In-Reply-To`. The parent is hydrated as context. A message that replies to one of the
agent's messages is addressed to the agent.
Not the same as Thread membership: on WhatsApp a reply stays inline in the room; on Slack
the only reply mechanism is a thread. See [threads, replies and edits](threads-replies-edits.md).
*Others:* OpenClaw `ReplyToId/Body/Sender`, Hermes `reply_to_message_id/text`,
ElizaOS `content.inReplyTo`.

### Revision and Edit
A Message has an ordered list of Revisions. An **Edit** is the event that creates a new
Revision. *Others:* Hermes `edit_revision`, Chat SDK `edited`/`editedAt`,
ElizaOS `editedAt`.

### Deletion
The event that a Message was removed (by its author or a moderator).

### Reaction
An emoji (or vote) added to or removed from a Message by a Participant.

### Interaction
A Participant's structured input in response to something the agent posted: button
click, select, modal submit, poll vote. Interactions answer **Asks** (below).

### Command
A Message (or slash command) that controls the system rather than talking to the agent:
`/stop`, `/new`, `/status`, `/approve`. Commands bypass Engagement and the Busy policy.

### Membership change
A Participant joined or left a Room; the agent itself was added or removed.

---

## 3. Gates (deciding what to do with an inbound message)

Three separate questions, answered in this order. The reviewed projects that keep them
separate (OpenClaw, NanoClaw) are the easiest to configure and reason about.

### Admission — *may this participant reach the agent at all?*
A security decision. Policy per Room kind: **Open**, **Allowlist**, **Pairing**,
**Closed**. Result: **Admitted**, **Refused**, or **Challenged** (pairing).
*Others:* OpenClaw "ingress"/`dmPolicy`/`groupPolicy`, Hermes "authorization",
nanobot `is_allowed`, NanoClaw `unknown_sender_policy` + `sender_scope`.

### Pairing
The flow that turns a Stranger into an admitted Participant: the agent replies with a
short code, the Owner approves it. Same word in OpenClaw, Hermes, nanobot, ElizaOS.

### Engagement — *is this message for the agent?*
A relevance decision for an admitted message, made from **addressing signals**:
Direct room, Mention, replies to the agent, Command, active Subscription, being in
**To** rather than Cc (email), a **Subject change** that targets the agent (assignment,
review request, label), pattern match, or the model's own judgement. Engagement produces
a **Disposition**.
**Engagement policy** per binding:
- **Always**: every message is a Request.
- **Mention**: only explicitly addressed messages are Requests.
- **Sticky**: Mention, then the conversation stays engaged (Subscription).
- **Pattern(regex)**: text match.
- **Judged**: a model decides (ElizaOS `shouldRespond`).
*Others:* OpenClaw "mention gating"/"activation", Hermes `require_mention`/free-response,
NanoClaw `engage_mode` (`pattern | mention | mention-sticky`), Chat SDK handler routing,
ElizaOS `shouldRespond`.

### Disposition
What an admitted message becomes for the agent:
- **Request**: a response is owed. The turn fails visibly if none is produced.
- **Observation**: the agent hears it and owes nothing; it may still speak.
- **Ignored**: not recorded.
*Why:* "Request" pairs with "Response". "Observation" is neutral about whether the agent
reacts.
*Others:* OpenClaw `InboundEventKind` = `user_request | room_event` and "stored for context
only"; Hermes `reply_expected` and `channel_context`; NanoClaw "engaged" vs
`ignored_message_policy = accumulate | drop`.

### Subscription
The agent's standing engagement with a Conversation, so follow-ups need no mention.
Started by being addressed (or by posting the root), ended by an explicit unsubscribe,
resolution of the Thread or Subject (review thread resolved, issue closed), or expiry.
*Others:* Chat SDK `thread.subscribe()`, NanoClaw `mention-sticky`, OpenClaw
`implicitMentions.threadParticipation`, Hermes `_mentioned_threads` wake checks.

### Provenance
Where a piece of input text comes from and how far it is trusted: **Owner**, **Member**,
**Stranger**, or **Content** (embedded material: quoted messages, forwarded mail,
webhook payloads, issue bodies). Content is shown to the model as data, never as
instructions. Identity claims also carry strength (OpenClaw grades them `verified`,
`asserted`, `unverified`, `mutable`; email `From:` is unverified unless DMARC passes).

---

## 4. Routing (agent side)

### Agent
A configured assistant: persona, instructions, tools, memory, workspace.
*Others:* OpenClaw `agentId`, Hermes **profile**, NanoClaw **agent group**, ElizaOS
agent/character.

### Binding
A rule connecting Conversations to an Agent, carrying the Engagement policy and Session
scope for that connection. Matched from most to least specific (thread, room, realm,
account, platform). Several Agents may be bound to one Room.
*Others:* OpenClaw `bindings[]` (+ broadcast groups), NanoClaw **wiring**
(`messaging_group_agents`), Hermes `profile_routes`.

### Session
The agent-side continuity for one or more Conversations: an append-only **transcript**
plus state, processed one Turn at a time. Sessions end only at an explicit **boundary**
(`/new`), never silently.
*Others:* the word is universal; ElizaOS uses room + memories instead.

### Session scope
How Conversations collapse into Sessions:
- **Agent**: everything the agent hears is one session (OpenClaw `dmScope: main` for DMs,
  NanoClaw `agent-shared`).
- **Room**: one session per Room.
- **Thread**: one session per Thread (falling back to Room).
- **Participant**: one session per Participant within a Room (Hermes default for groups).
These compose (Room × Participant). The **Session key** is the scope applied to a
Conversation.

### Origin
The Conversation (and Message) a Turn's input came from. Responses go to the Origin by
default.
*Others:* OpenClaw `OriginatingChannel/To`, `lastRoute`; Hermes `origin`.

### Home
A designated Conversation for output that has no Origin (schedules, background
completions).
*Others:* Hermes "home channel", NanoClaw "destinations".

---

## 5. Running

### Input
Anything appended to a Session: a Request, an Observation, a **Notice** (edit, deletion,
reaction, membership change rendered as text), or a **Trigger** input.

### Trigger
A non-conversational cause of a Turn: **Schedule** (cron, reminder), **Webhook**,
**Completion** (a background job or sub-agent finished), **Heartbeat**.
*Others:* OpenClaw `InternalTurnSource`, NanoClaw `messages_in.kind` = `task | webhook | system`.

### Turn
One run of the agent over a batch of Inputs, producing outputs and ending in an
**Outcome**: **Responded**, **Silent**, **Failed**, **Cancelled**.
*Others:* "turn" in OpenClaw, Hermes, nanobot; "run" in OpenClaw docs.

### Coalescing
Batching Inputs that arrive close together *before* a Turn starts, with a quiet window
and a maximum wait. Keyed by Conversation and author, or by Subject for webhooks.
*Others:* OpenClaw "debounce"/"collect", Hermes webhook "coalesce", Chat SDK "burst",
ElizaOS "coalesce".

### Busy policy
What happens to a new Input when the Session already has a Turn running:
- **Steer**: add it to the running Turn at the next step boundary.
- **Queue**: run it as its own Turn afterwards (FIFO).
- **Collect**: merge everything that arrived into one later Turn.
- **Interrupt**: cancel the running Turn and start a new one.
- **Drop**: discard it.
*Others:* OpenClaw `steer | followup | collect | interrupt`, Hermes `steer | queue | interrupt`,
nanobot injection (= Steer), Chat SDK `drop | queue | burst | debounce | concurrent`
(its `queue` = Collect-latest).

### Supersession
An Edit (or Deletion) replacing an Input that has not yet produced visible output; the
pending or running Turn is cancelled and the new Revision takes its place.
*Others:* OpenClaw Telegram "supersede", ElizaOS "superseded by an edit".

### Cancellation
Stopping a running Turn on request (`/stop`, Slack's stop button).

---

## 6. Speaking (outbound)

### Response
The agent's answer to a Request, delivered to the Origin.
*Others:* OpenClaw "reply payload", Hermes `final_response`, nanobot `OutboundMessage`.

### Post
A message the agent chooses to send through a tool, to the Origin or any other
Conversation it is allowed to reach. In quiet rooms Posting is the only way to speak
(OpenClaw `visibleReplies: "message_tool"`).

### Silence
An explicit decision to produce no Response. Valid for Observations; for a Request it is
an Outcome that should be deliberate and visible in logs.
*Others:* OpenClaw/Hermes `NO_REPLY`.

### Placement
Where in the Conversation an output lands: **Inline** (in the room), **Threaded** (in the
thread of the trigger, creating it if needed), **Quoting** (replies_to the trigger), or
**Broadcast** (threaded and also shown in the room).
*Others:* OpenClaw `replyToMode = off | first | all | batched`, Slack `reply_broadcast`,
Hermes/Discord auto-thread.

### Draft
A provisional outbound message that is edited in place while the Turn runs (streaming)
and then **sealed** as the final Response. Only on platforms with the edit Capability;
elsewhere the Response is buffered and sent once.
*Others:* OpenClaw "draft stream"/"preview", Hermes "draft stream" + "seal".

### Delivery and Receipt
A Delivery is one accepted send; its **Receipt** holds the platform message ids, so the
agent can later edit, delete or thread under what it sent. Deliveries may be partial.

### Indicator
A transient signal of the agent's state on the platform: **Typing**, **Acknowledgement**
(👀 on receipt), **Status** (reactions or a progress card cycling through queued,
thinking, tool use, done, error).

### Ask
A question posted to a Person that expects an **Interaction** answer: a choice,
clarification, or **Approval** of a privileged action (routed to an approver, often in
their Direct room).
*Others:* NanoClaw `ask_user_question` + approvals, Hermes clarify/approve, OpenClaw
question actions and exec approvals.

### Action
An effect on the Platform that is not a message: react, pin, label, assign, close an
issue, create a thread. Subject-based platforms need many more Actions than chat.

---

## Name collisions to avoid

| Word | Means here | Also used for (avoid that sense) |
|---|---|---|
| channel | a kind of Room | OpenClaw/nanobot: a platform integration |
| workspace | (not used) | Slack realm; agent file system |
| group | a kind of Room | NanoClaw "agent group" (an Agent), "messaging group" (a Room) |
| session | agent-side continuity | Linear "AgentSession" (a platform-side Conversation with progress) |
| thread | sub-conversation | Chat SDK: every conversation; OS threads |
| reply | (verb only; relation `replies_to`) | the agent's output (use Response) |
| room | a place with members | Matrix: also the only place type |
| subject | the work item | email Subject header (that is the Subject's title) |
| event | a platform occurrence | agent runtime/telemetry events |

## Cross-project mapping

| Glossary | OpenClaw | Hermes | nanobot | NanoClaw | Chat SDK | ElizaOS |
|---|---|---|---|---|---|---|
| Platform | channel | Platform | channel | channel_type | adapter name | source |
| Account | account | bot / transport profile | (one per channel) | instance | adapter | (one) |
| Realm | guild / team | scope_id, guild_id | — | — | (in ids) | World |
| Room | peer + chat type | chat_id + chat_type | chat_id | messaging group | Channel | Room |
| Thread | `:thread:` / `:topic:` | thread_id | thread_ts in key | thread_id | Thread | Room(THREAD) |
| Conversation | route | SessionSource | channel:chat_id | platform_id+thread_id | Thread | Room |
| Participant | Sender | user | sender_id | user | Author | Entity |
| Admission | ingress | authorization | is_allowed | unknown_sender_policy, sender_scope | (app code) | allowlist / DM access |
| Engagement | mention gating / activation | require_mention, wake checks | group_policy | engage_mode | handler routing | shouldRespond |
| Request / Observation | user_request / room_event | reply_expected / channel_context | — | engaged / accumulate | — | respond / ignore |
| Subscription | thread participation | mentioned threads | — | mention-sticky | subscribe | — |
| Agent | agent | profile | (one) | agent group | (app) | agent |
| Binding | binding | profile route | — | wiring | — | — |
| Session scope | dmScope, groupScope | group/thread_sessions_per_user | key override | session_mode | (thread) | (room) |
| Busy policy | queue mode | busy mode | inject | (container inbox) | concurrency | (queue per message) |
| Response / Post | reply / message tool | final / send | outbound | messages_out | thread.post | callback |
| Draft | draft stream, preview | draft stream, seal | stream edits | — | post + edit stream | draft stream |

## Gleam sketch

```gleam
// Places and people ---------------------------------------------------------

pub type Platform { Platform(name: String, capabilities: Capabilities) }

pub type Account { Account(platform: Platform, id: String, kind: AccountKind) }
pub type AccountKind { Bot Personal }

pub type Realm { Realm(platform: Platform, id: String) }

pub type RoomKind { Direct Group Channel }
pub type Room { Room(realm: Option(Realm), id: String, kind: RoomKind) }

pub type Thread { Thread(id: String, root: Option(MessageId), subject: Option(Subject)) }

pub type Conversation {
  Conversation(account: Account, room: Option(Room), thread: Option(Thread))
}

pub type Audience { Private Members Public Unknown }

pub type ParticipantKind { Person Bot Self }
pub type Participant { Participant(id: String, name: String, kind: ParticipantKind) }

pub type Role { Owner Admin Member Stranger }

pub type Subject {
  Subject(kind: String, id: String, title: String, state: String, url: String)
}

// What happens ---------------------------------------------------------------

pub type Message {
  Message(
    id: MessageId,
    conversation: Conversation,
    author: Participant,
    body: Body,
    mentions: List(Participant),
    replies_to: Option(MessageId),
    revision: Int,
    audience: Audience,
  )
}

pub type Inbound {
  Posted(Message)
  Edited(Message, previous: Option(Message))
  Deleted(Conversation, MessageId)
  Reacted(Conversation, MessageId, by: Participant, emoji: String, added: Bool)
  Interacted(Conversation, ask: AskId, by: Participant, value: Dynamic)
  Commanded(Conversation, by: Participant, command: String, args: String)
  MembershipChanged(Room, Participant, joined: Bool)
}

// Gates ----------------------------------------------------------------------

pub type Admission { Admitted(Role) Refused(reason: String) Challenged(pairing_code: String) }

pub type EngagementPolicy { Always Mention Sticky Pattern(String) Judged }

pub type Disposition { Request Observation Ignored }

pub type Provenance { FromOwner FromMember FromStranger Content(source: String) }

// Routing --------------------------------------------------------------------

pub type SessionScope { PerAgent PerRoom PerThread PerParticipant(SessionScope) }

pub type Binding {
  Binding(matches: ConversationPattern, agent: AgentId, engagement: EngagementPolicy,
    scope: SessionScope, busy: BusyPolicy)
}

// Running --------------------------------------------------------------------

pub type Trigger { Schedule(String) Webhook(source: String) Completion(job: String) Heartbeat }

pub type Input {
  FromMessage(Message, Disposition, Provenance)
  Notice(Inbound)          // edits, deletions, reactions rendered as context
  Triggered(Trigger, payload: String)
}

pub type BusyPolicy { Steer Queue Collect Interrupt Drop }

pub type Outcome { Responded Silent Failed(String) Cancelled }

// Speaking -------------------------------------------------------------------

pub type Placement { Inline Threaded Quoting Broadcast }

pub type Output {
  Response(Body, Placement)                       // to the Origin
  Post(to: Conversation, body: Body, placement: Placement)
  Draft(id: DraftId, text: String, sealed: Bool)
  Indicate(Indicator)                             // Typing | Acknowledged | Status(String)
  Ask(id: AskId, to: Participant, question: String, options: List(String))
  Act(Action)                                     // react, label, assign, close, pin ...
  Silence
}
```
