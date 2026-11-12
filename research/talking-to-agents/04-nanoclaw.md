# NanoClaw: inbound message pipeline

Source: `qwibitai/nanoclaw` @ `62dc090` (2026-11-11), the v2 rewrite. TypeScript host
process plus one container per session. Platform integrations are either native
adapters (WhatsApp via Baileys, Gmail) or Vercel Chat SDK adapters wrapped by a bridge.

Key sources read:
`CLAUDE.md` (entity model), `docs/architecture.md`, `docs/isolation-model.md`,
`src/types.ts` (`MessagingGroup`, `MessagingGroupAgent`, `EngageMode`, ...),
`src/router.ts` (`routeInbound`, `evaluateEngage`), `src/channels/adapter.ts`
(`InboundEvent`).

## Shape

```text
platform event -> channel adapter (filter, extract platformId + threadId, isMention)
  -> router: messaging group (auto-register?) -> user -> unknown-sender policy
  -> fan-out over wirings (messaging group <-> agent group):
       engage? + access? + sender scope?  -> session -> inbound.db (trigger) -> wake container
       else accumulate?                   -> inbound.db (context only)
       else drop
  -> container agent-runner polls inbound.db -> writes outbound.db (text | edit | reaction | card)
  -> host delivery poll -> adapter.deliver (routing copied from the triggering input)
```

NanoClaw vocabulary is the most explicit entity model of the projects reviewed:

| Term | Meaning |
|---|---|
| **user** | a platform identifier, namespaced `"<channel>:<handle>"`; no cross-platform linking |
| **messaging group** | one chat/channel on one platform (`channel_type`, `instance`, `platform_id`, `is_group`) |
| **agent group** | a workspace: memory, `CLAUDE.md`, skills, container config |
| **wiring** (`messaging_group_agents`) | many-to-many link with `engage_mode`, `sender_scope`, `ignored_message_policy`, `session_mode`, `priority` |
| **session** | `agent_group + messaging_group + thread_id` -> one container + two DBs |
| **owner / admin / member** | user-level privilege; admin may be scoped to one agent group |

## Pseudocode

```gleam
pub type EngageMode {
  Pattern(regex: String)   // "." = every message
  Mention                  // platform-confirmed mention of the bot
  MentionSticky            // mention, or this agent already woke in this thread
}

pub type SenderScope { All Known }
pub type IgnoredMessagePolicy { Drop Accumulate }
pub type SessionMode { Shared PerThread AgentShared }
pub type UnknownSenderPolicy { Strict RequestApproval DeclineNotify Public }

pub type InboundEvent {
  InboundEvent(
    channel_type: String,        // "whatsapp", "slack", "discord", "github" ...
    instance: Option(String),    // adapter instance (which bot)
    platform_id: String,         // the chat / channel / email thread
    thread_id: Option(String),   // Slack thread, GitHub PR comment thread ...
    message: Message,            // id, kind (chat | chat-sdk), content, timestamp, is_mention, is_group
    reply_to: Option(DeliveryAddress),
  )
}

// ---- Adapter ------------------------------------------------------------------
// The adapter filters (stateless regex or stateful "bot was mentioned in this
// thread") and returns platform-level ids only. It knows nothing of agents.

pub fn adapter_on_event(raw) -> Option(InboundEvent) {
  use <- bool.guard(from_self(raw) || !worth_forwarding(raw), None)
  Some(InboundEvent(
    channel_type: "slack",
    instance: Some(instance_name),
    platform_id: raw.channel,
    thread_id: thread_policy(raw),  // unique per thread => per-thread sessions
    message: Message(id: raw.ts, kind: ChatSdk, content: serialize(raw),
      is_mention: raw.is_mention, is_group: raw.channel_type != "im"),
    reply_to: None,
  ))
}

// ---- Router --------------------------------------------------------------------

pub fn route_inbound(event: InboundEvent) -> Nil {
  let mg = case find_messaging_group(event.channel_type, event.instance, event.platform_id) {
    Some(mg) -> mg
    None -> auto_register_or_escalate(event)   // channel-type specific rules; owner may deny
  }
  use <- bool.guard(option.is_some(mg.denied_at), Nil)
  let user = upsert_user(event.channel_type <> ":" <> sender_handle(event))

  case is_known(user, mg), mg.unknown_sender_policy {
    False, Strict -> Nil
    False, DeclineNotify -> notify_declined(event)
    False, RequestApproval -> request_owner_approval(user, mg)   // card to approver's DM
    _, _ -> {
      use <- command_gate(event, user)          // admin commands checked against user_roles
      fan_out(event, mg, user)
    }
  }
}

fn fan_out(event, mg, user) -> Nil {
  list.each(wirings_for(mg) |> sort_by_priority, fn(wiring) {
    let engages = evaluate_engage(wiring, event.message, mg, event.thread_id)
    let access_ok = can_access_agent_group(user, wiring.agent_group_id) // owner/admin/member
    let scope_ok = wiring.sender_scope == All || is_member(user, wiring.agent_group_id)
    case engages && access_ok && scope_ok, wiring.ignored_message_policy {
      True, _ -> {
        let session = resolve_session(wiring, mg, event.thread_id)
        session_db.write_messages_in(session, event, trigger: True)
        adapter.set_typing(event)
        wake_container(session)
      }
      False, Accumulate -> {
        let session = resolve_session(wiring, mg, event.thread_id)
        session_db.write_messages_in(session, event, trigger: False)  // silent context
      }
      False, Drop -> Nil
    }
  })
}

fn evaluate_engage(wiring, message, mg, thread_id) -> Bool {
  case wiring.engage_mode {
    Pattern(".") -> True
    Pattern(re) -> regex.check(re, message.text)
    Mention -> message.is_mention
    MentionSticky ->
      message.is_mention
      || { mg.is_group && thread_has_woken_session(wiring.agent_group_id, mg.id, thread_id) }
  }
}

fn resolve_session(wiring, mg, thread_id) -> Session {
  let mode = case adapter_supports_threads(mg), wiring.session_mode, mg.is_group {
    True, Shared, True -> PerThread       // threads enabled in a group force per-thread
    _, mode, _ -> mode
  }
  case mode {
    AgentShared -> find_or_create(agent: wiring.agent_group_id)                // all chats, one session
    Shared -> find_or_create(agent: wiring.agent_group_id, group: mg.id)
    PerThread -> find_or_create(agent: wiring.agent_group_id, group: mg.id, thread: thread_id)
  }
}

// ---- Container + delivery --------------------------------------------------------

pub fn agent_runner_loop(session) -> Nil {
  let inputs = inbound_db.poll_new(session)       // chat | task | webhook | system
  let output = provider.run(inputs)
  // output rows copy routing (kind, platform_id, channel_type, thread_id) from input
  outbound_db.write(session, output)              // {text} | {operation: edit | reaction | ask_question}
}

pub fn host_delivery_poll(session) -> Nil {
  list.each(outbound_db.unread(session), fn(row) {
    use <- bool.guard(!permitted_destination(session, row.routing), Nil)
    case row.content.operation {
      None -> adapter.send(row.routing, row.content)
      Some(Edit(message_id, text)) -> adapter.edit_message(message_id, text)
      Some(Reaction(message_id, emoji)) -> adapter.add_reaction(message_id, emoji)
      Some(AskQuestion(..)) -> adapter.post_card(..)  // answer returns as a messages_in row
    }
  })
}
```

## Platform notes

- Channel **capability differences** are handled by graceful degradation in the bridge:
  Slack (cards, modals, streaming, reactions), Discord (embeds, buttons, post+edit
  streaming), WhatsApp Cloud API (DMs only, reply buttons, no streaming or reactions),
  GitHub/Linear (markdown comments, no interactivity).
- Inbound **edits** are not handled; outbound edits and reactions are agent tool calls.
- **Agent-to-agent** messaging is a normal outbound row with `channel_type: "agent"`.
- **Approvals** are routed to an approver's DM (scoped admins > global admins > owner).

## Distinctive ideas

- A clean separation between **messaging group** (place) and **agent group** (brain),
  joined by a **wiring** that carries all engagement and session policy.
- **Isolation levels** as a user-facing concept: shared session (`agent-shared`, e.g.
  Slack + GitHub webhooks in one transcript), same agent / separate sessions, separate
  agents.
- **Everything is a message**: chat, scheduled task, webhook, and system results all
  arrive as `messages_in` rows with a `kind`.
