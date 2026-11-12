# Talking to agents: a comparative review

Goal: find a general vocabulary (a domain-specific language) for the concept of people
talking to agents through messaging platforms, by reading how existing agent systems
process an incoming Slack, Discord or WhatsApp message, in direct messages and in
group/channel chats.

## Projects reviewed

| Project | Revision | What it is | File |
|---|---|---|---|
| [OpenClaw](https://github.com/openclaw/openclaw) | `2c8868bff` | Personal agent gateway, TypeScript, dozens of messaging channels | [01-openclaw.md](01-openclaw.md) |
| [Hermes Agent](https://github.com/NousResearch/hermes-agent) | `a41cb47c` | Agent with a multi-platform messaging gateway, Python | [02-hermes-agent.md](02-hermes-agent.md) |
| [nanobot](https://github.com/HKUDS/nanobot) | `9f7ae6f` | Lightweight agent, channels on a message bus, Python | [03-nanobot.md](03-nanobot.md) |
| [NanoClaw](https://github.com/qwibitai/nanoclaw) | `62dc090` | Container-per-session agent host with an explicit entity model | [04-nanoclaw.md](04-nanoclaw.md) |
| [Chat SDK](https://github.com/vercel/chat) | `d0ff1dc` | Cross-platform bot library (Slack ... GitHub, Linear, Gmail) | [05-chat-sdk.md](05-chat-sdk.md) |
| [ElizaOS](https://github.com/elizaos/eliza) | `1d5a8983` | Agent runtime with World/Room/Entity model | [06-elizaos.md](06-elizaos.md) |

"Hermes" and "Hermes Agent" in the original request were taken to be the same project.
Chat SDK is a library rather than an agent; it was added to the three extra projects
because it is the most deliberate existing attempt at a shared vocabulary and because it
already supports GitHub and email.

Each project file has Gleam-syntax pseudocode for the inbound pipeline, using **that
project's own names**, so the files can be compared side by side. The pseudocode is a
reading aid, not a translation: helpers are elided and some branches are merged.

## Outputs

- [glossary.md](glossary.md): the proposed vocabulary, with definitions, reasons for
  each name, names to avoid, a cross-project mapping table, and a Gleam type sketch.
- [threads-replies-edits.md](threads-replies-edits.md): second review focused on threads,
  `replies_to`, edits and deletions, with the glossary changes it caused.
- [other-channels.md](other-channels.md): GitHub issues/PRs and email as front ends.

## The common pipeline

Every project implements the same stages, though they draw the boundaries in different
places:

```text
 Platform event
   │  Integration: normalise to a Message in a Conversation (room, thread, author, body,
   │               mentions, replies_to); drop own messages; dedupe redeliveries
   ▼
 Admission      may this participant reach the agent?       open | allowlist | pairing | closed
   ▼
 Engagement     is this message for the agent?              mention | sticky | always | pattern | judged
   │            → Disposition: Request | Observation | Ignored
   ▼
 Routing        which Agent (Binding) and which Session (Session scope)?
   ▼
 Coalescing     batch a burst of inputs into one turn
   ▼
 Busy policy    a turn is already running: steer | queue | collect | interrupt | drop
   ▼
 Turn           agent runs over inputs; Indicators (typing, status) while it works
   ▼
 Speaking       Response to Origin (Placement: inline | threaded | quoting), Posts elsewhere,
                Drafts sealed into finals, Asks, Actions, or Silence; Receipts recorded
```

## Main findings

1. **Admission, Engagement and Disposition are three separate decisions.** OpenClaw and
   NanoClaw separate them and are the clearest; Hermes and nanobot fold them into adapter
   gates, which spreads mention logic across every platform.
2. **"Is a response owed?" deserves a name.** OpenClaw's `user_request` vs `room_event`,
   NanoClaw's engaged vs `accumulate`, and Hermes' `reply_expected` are the same idea:
   **Request** vs **Observation**. Observations let an agent follow a room without
   being forced to speak.
3. **Place and memory are different things.** A Conversation (platform side) maps to a
   Session (agent side) through a **Session scope**. The projects disagree on defaults:
   OpenClaw puts all DMs in one main session and one session per group; Hermes gives each
   person their own session inside a group but shares threads; NanoClaw makes it a
   per-wiring choice including "one session for everything this agent hears".
4. **Threads need explicit Subscription state.** Every project that handles threads
   well remembers where the agent was addressed so follow-ups need no mention.
5. **Edits are state-dependent.** The projects' edit behaviours (ignore, notice,
   supersede, re-evaluate) are each correct for one state of the edited message;
   combined they give one policy table.
6. **"Channel" is the most dangerous word in this domain.** Half the projects use it for
   the platform integration and every platform uses it for a room. The glossary uses
   Platform / Integration for the former and keeps "channel" for the Slack/Discord sense.
7. **GitHub and email fit with additions**: a **Subject** with state, addressing by
   Subject change (assignment), optional Rooms, explicit **Audience** (To/Cc), Actions
   as first-class output, and identity strength in Provenance.

## Method and limits

- Read each project's architecture docs first, then the code for the Slack path in
  detail and the Discord and WhatsApp paths for their differences. Line-level claims were
  checked against the source at the revisions above; these projects move quickly.
- ElizaOS has no WhatsApp plugin at this revision; Discord was reviewed instead.
- Configuration defaults are quoted as documented and may differ per deployment.
