# OpenClaw: inbound message pipeline

Source: `openclaw/openclaw` @ `2c8868bff` (2026-11-12). TypeScript gateway; every
messaging platform is a "channel plugin" under `extensions/<name>`.

Key sources read:
`docs/concepts/messages.md`, `docs/channels/channel-routing.md`, `docs/channels/groups.md`,
`docs/channels/group-messages.md` (WhatsApp), `docs/channels/slack/threads-and-sessions.md`,
`docs/channels/slack/events.md`, `docs/channels/ambient-room-events.md`,
`docs/plugins/sdk-channel-inbound.md`, `docs/plugins/sdk-channel-ingress.md`,
`src/auto-reply/templating.ts` (`MsgContext`), `src/channels/inbound-event/kind.ts`,
`extensions/slack/src/monitor/events/messages.ts`.

## Shape

```text
platform event -> ingest (normalise facts) -> dedupe -> route (bindings -> agent, session key)
  -> ingress (admission: DM/group policy, pairing, mention activation)
  -> build context -> debounce -> queue (steer/followup/collect/interrupt)
  -> agent run -> reply payloads -> delivery (threading, chunking, drafts, receipts)
```

OpenClaw's own vocabulary: **channel** = platform plugin (slack, discord, whatsapp),
**account** = one login on that platform, **peer** = the other side of a conversation,
**chat type** = `direct | group | channel`, **session key** = context bucket,
**binding** = config rule mapping inbound traffic to an **agent**.
The "channel" vs Slack/Discord "channel" collision is the main naming hazard in this codebase.

## Pseudocode

```gleam
// ---- Types (simplified from MsgContext / ingress facts) --------------------

pub type ChatType {
  Direct
  Group      // WhatsApp group, Slack MPIM, Telegram group
  Channel    // Slack channel, Discord guild channel
}

/// The "two kinds of admitted input" (src/channels/inbound-event/kind.ts)
pub type InboundEventKind {
  UserRequest   // a result is owed
  RoomEvent     // ambient chatter; the agent may stay silent
}

pub type InboundFacts {
  InboundFacts(
    channel: String,            // "slack" | "discord" | "whatsapp" ...
    account_id: String,         // which of our logins received it
    chat_type: ChatType,
    peer_id: String,            // DM user, group JID, channel id
    thread_id: Option(String),  // Slack thread_ts, Discord thread, Telegram topic
    guild_or_team: Option(String),
    message_id: String,
    sender: Sender,             // id, name, is_bot
    body: String,
    media: List(MediaFact),
    reply_to: Option(ReplyRef), // ReplyToId / ReplyToBody / ReplyToSender
    mentions_bot: Bool,         // native @mention or configured mentionPatterns
  )
}

// ---- Entry point per platform event ----------------------------------------

pub fn on_platform_event(raw: PlatformEvent, account: AccountId) -> Nil {
  case classify(raw) {
    // Slack: message_changed / message_deleted, reactions, member join/leave,
    // pins, channel renames -> become *system events* attached to the routed
    // session; they never start a user turn on their own.
    Edited(..) | Deleted(..) | Reaction(..) | Membership(..) | Pin(..) ->
      enqueue_system_event(route_for(raw), describe(raw))
    // Block Kit actions, shortcuts, modals -> structured "Slack interaction" events
    Interaction(i) -> enqueue_system_event(route_for(raw), interaction_summary(i))
    // Slack "also send to channel" thread replies are treated as normal messages
    NewMessage(msg) -> handle_message(ingest(msg, account))
  }
}

fn handle_message(facts: InboundFacts) -> Nil {
  // 1. Dedupe redelivery: key = agent scope + route (channel, peer, account, thread) + message id
  use <- bool.guard(dedupe_cache.seen(facts), Nil)

  // 2. Route: pick ONE agent by binding precedence
  //    exact peer > parent peer (thread inherits) > peer wildcard > guild+roles
  //    > guild > team > account > channel > fallback owner
  let route = resolve_agent_route(config.bindings, facts)
  let session_key = session_key_for(route.agent_id, facts, route.session_scope)

  // 3. Ingress / admission (core-owned policy; plugin supplies facts only)
  let ingress =
    ingress.resolve(
      subject: facts.sender,
      conversation: facts.chat_type,
      event: Message(may_pair: facts.chat_type == Direct),
      policy: #(dm_policy, group_policy),   // pairing|allowlist|open|disabled
      allow_from: config.allow_from,
      group_allow_from: config.group_allow_from,
      command: parse_control_command(facts.body),
    )
  case ingress.decision {
    Refused(PairingRequired) -> send_pairing_code(facts)   // 8-char code, 1h expiry
    Refused(reason) -> log_inbound_drop(reason)
    Admitted(activation) -> admitted(facts, route, session_key, activation)
  }
}

fn admitted(facts, route, session_key, activation) -> Nil {
  // 4. Mention gating / activation decides *kind*, or stores as pending context
  let kind = case facts.chat_type, activation {
    Direct, _ -> Ok(UserRequest)
    _, Mentioned | Command -> Ok(UserRequest)
    // implicit mentions: reply to one of the bot's messages, or follow-up in a
    // thread the bot already participates in (implicitMentions.*)
    _, ImplicitMention(_) -> Ok(UserRequest)
    _, Unmentioned if require_mention(facts) -> {
      pending_history.append(session_key, facts)   // "for context" buffer
      Error(Nil)
    }
    _, Unmentioned if config.group_chat.unmentioned_inbound == "room_event" ->
      Ok(RoomEvent)
    _, Unmentioned -> Ok(UserRequest)                // always-on room
  }
  use kind <- result.try(kind)

  // 5. Build the model-facing context
  let ctx =
    build_context(
      facts,
      inbound_event_kind: kind,
      history: pending_history.take(session_key),   // "[Chat messages since your last reply]"
      reply_to: hydrate_parent(facts.reply_to),      // "[Replying to ...]" block
      thread_starter: fetch_thread_root(facts),       // Slack thread seeding
      untrusted: channel_metadata(facts),             // topic, purpose, members
    )

  // 6. Broadcast groups: several agents may be bound to one room
  case broadcast_participants(facts) {
    [] -> enqueue(session_key, ctx)
    agents -> list.each(agents, fn(a) { enqueue(session_key_for(a, facts), ctx) })
  }
}

fn enqueue(session_key, ctx) -> Nil {
  // 7. Debounce bursts from same sender (per channel; text only; commands bypass)
  use batch <- debounce(session_key, ctx, window: debounce_ms(ctx.channel))

  // 8. Queue mode when a run is already active for this session
  case active_run(session_key) {
    None -> start_run(session_key, batch)
    Some(run) ->
      case config.messages.queue.mode {
        "steer" -> inject_into(run, batch)          // default
        "followup" -> queue_after(run, batch)
        "collect" -> merge_into_next_turn(run, batch)
        "interrupt" -> { abort(run) start_run(session_key, batch) }
      }
  }
}

fn start_run(session_key, ctx) -> Nil {
  // 9. Agent run streams; outputs are reply payloads, or explicit message-tool sends
  let outcome = agent.run(session_key, ctx)
  case outcome.final_text {
    "NO_REPLY" -> Nil                                // explicit silence
    text ->
      case ctx.visible_replies {
        Automatic -> deliver(ctx.origin, text)
        MessageToolOnly -> Nil                       // agent already used message(action=send)
      }
  }
}

fn deliver(origin: Route, payload) -> Nil {
  // replyToMode: off | first | all | batched ; [[reply_to_current]] tags
  let target = reply_target(origin, config.reply_to_mode)
  payload
  |> chunk(channel_text_limit(origin.channel))       // avoid splitting code fences
  |> list.each(fn(chunk) { outbound.send_durable(target, chunk) }) // returns receipts
}

fn session_key_for(agent_id, facts, scope) -> String {
  let base = case facts.chat_type, scope.dm_scope {
    Direct, "main" -> "agent:" <> agent_id <> ":main"   // all DMs, all platforms
    Direct, "per-peer" -> ... // per-channel-peer, per-account-channel-peer
    Group, _ -> "agent:" <> agent_id <> ":" <> facts.channel <> ":group:" <> facts.peer_id
    Channel, _ -> "agent:" <> agent_id <> ":" <> facts.channel <> ":channel:" <> facts.peer_id
  }
  case facts.thread_id {
    Some(t) -> base <> ":thread:" <> t   // Slack/Discord threads; Telegram uses :topic:
    None -> base
  }
}
```

## Platform notes

- **Slack.** DM = `direct`, MPIM = `group`, channel = `channel`. Thread replies get a
  `:thread:<thread_ts>` session; a mention at top level is *seeded* into the thread session
  it will create, so root + replies share one session. `implicitMentions.replyToBot` and
  `implicitMentions.threadParticipation` (default on) let unmentioned follow-ups through.
  Edits/deletes are system events. Agent View DMs: every top-level composer message is a
  new root and a new session.
- **Discord.** Guild channel = `channel`; threads append `:thread:<id>`; routing can match
  on guild + member roles. Reactions become system events (per-guild mode).
- **WhatsApp.** Runs as a linked device on *your own* number (no separate bot user).
  Groups default to `allowlist` policy and `mention` activation; `/activation always` is
  owner-only. Mention = native `mentionedJids`, configured regex, `@<number>`, or a quoted
  reply to the bot. Pending group messages (default 50) are injected as context and cleared
  after the run. Ack reaction (`👀`) and lifecycle status reactions show progress.
- **Telegram** (for comparison): an edit of a still-pending message *supersedes* it
  (`telegram-ingress-supersede.ts`).

## Distinctive ideas

- Separation of **admission** (may this sender reach the agent) from **activation**
  (should this message start a turn) and from **event kind** (is a reply owed).
- **Ambient room events** + `visibleReplies: "message_tool"`: the agent listens to the
  room and must *choose* to speak via a tool, instead of emitting `NO_REPLY`.
- Strong output contract: one logical reply payload, durable delivery, receipts,
  `final` vs progress sends, partial-delivery errors.
