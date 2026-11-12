# Hermes Agent: inbound message pipeline

Source: `NousResearch/hermes-agent` @ `a41cb47c` (2026-11-11). Python "messaging gateway";
each platform is an adapter plugin under `plugins/platforms/<name>/adapter.py` over
`gateway/platforms/base.py`.

> The request mentioned "hermes" and "hermes agent" separately. Both resolve to this
> repository (Nous Research's Hermes Agent), so it is reviewed once.

Key sources read:
`gateway/AGENTS.md`, `gateway/platforms/event.py` (`MessageEvent`), `gateway/session.py`
(`SessionSource`, `build_session_key`), `plugins/platforms/slack/adapter.py`
(channel gate, wake checks, `message_changed`),
`website/docs/developer-guide/gateway-internals.md`,
`website/docs/developer-guide/gateway-session-lifecycle.md`,
`website/docs/user-guide/messaging/{discord,whatsapp,email,webhooks}.md`.

## Shape

```text
adapter receives raw event -> adapter-side gate (allowed channels, mention, wake checks)
  -> MessageEvent { text, source: SessionSource, reply_to_*, media, ... }
  -> canonicalize identity (which bot received it, which profile runs it)
  -> session key -> guard 1 (adapter: session busy? park in pending slot)
  -> runner: authorize (allowlist / pairing) -> slash command? -> guard 2 (busy policy)
  -> AIAgent turn -> stream consumer -> delivery adapter (draft edits, seal final)
```

Hermes vocabulary: **platform** (slack, discord, whatsapp), **adapter**, **source**
(`SessionSource`: where a message came from), **chat type** = `dm | group | channel | thread`,
**session key**, **profile** (an agent persona/home; several can share one bot via
"multiplexing"), **home channel** (default destination for cron/background output).

## Pseudocode

```gleam
pub type SessionSource {
  SessionSource(
    platform: Platform,
    chat_id: String,
    chat_type: String,              // "dm" | "group" | "channel" | "thread"
    user_id: Option(String),
    user_name: Option(String),
    thread_id: Option(String),      // forum topic, Discord thread, Slack thread
    parent_chat_id: Option(String), // parent channel when chat_id is a thread
    scope_id: Option(String),       // Slack workspace
    guild_id: Option(String),
    message_id: Option(String),     // triggering message (reply/react target)
    is_bot: Bool,
    profile: Option(String),
  )
}

pub type MessageEvent {
  MessageEvent(
    text: String,
    message_type: MessageType,      // Text | Photo | Voice | Document | Command ...
    source: SessionSource,
    message_id: Option(String),
    media_urls: List(String),
    reply_to_message_id: Option(String),
    reply_to_text: Option(String),
    reply_to_is_own_message: Bool,  // user replied to the bot
    channel_context: Option(String),// history backfilled under require_mention
    reply_expected: Option(Bool),   // was this addressed to us?
    edit_revision: Option(String),  // one edit of a message (Telegram update_id)
    internal: Bool,                 // synthetic (background notification)
  )
}

// ---- Slack adapter ---------------------------------------------------------

pub fn on_slack_event(event: SlackEvent) -> Nil {
  case event.subtype {
    // An edit of a message that was NOT routed to the agent is re-run as a new
    // message (e.g. the user edited in the @mention). Edits of already-routed
    // messages are dropped.
    Some("message_changed") ->
      case normalize_changed_message(event) {
        None -> Nil
        Some(e) -> on_slack_message(e)
      }
    _ -> on_slack_message(event)
  }
}

fn on_slack_message(event) -> Nil {
  let is_dm = event.channel_type == "im"
  use <- bool.guard(early_reject_unauthorized(event.user, event.channel, is_dm), Nil)
  let is_mentioned = mentions_bot(event)
  let is_thread_reply = option.is_some(event.thread_ts) && event.thread_ts != Some(event.ts)

  use <- bool.guard(
    !is_dm && !channel_gate_allows(event, is_mentioned, is_thread_reply),
    Nil,
  )
  let text =
    event.text
    |> strip_bot_mention
    |> append_block_text(event.blocks)   // Block Kit / quoted / forwarded content
    |> append_link_unfurls(event.attachments)

  let source =
    build_source(
      chat_id: event.channel,
      chat_type: case is_dm, event.thread_ts { True, _ -> "dm"  _, Some(_) -> "thread"  _, None -> "group" },
      user_id: event.user,
      thread_id: thread_for(event),     // reply in a thread unless configured inline
      scope_id: event.team,
    )
  base_adapter.handle_message(MessageEvent(
    ..default_event(),
    text: text,
    source: source,
    message_id: Some(event.ts),
    channel_context: backfill_history_if_mentioned(event),
    reply_expected: Some(is_mentioned || is_dm),
  ))
}

/// Channel / MPIM gate (plugins/platforms/slack/adapter.py::_channel_gate_allows)
fn channel_gate_allows(event, is_mentioned, is_thread_reply) -> Bool {
  case Nil {
    _ if !in_allowed_channels(event.channel) -> False
    _ if addressed_to_other_user(event) && !is_mentioned -> False
    _ if strict_mention() && !is_free_channel(event.channel) && !is_mentioned -> False
    _ if thread_require_mention() && is_thread_reply && !is_mentioned -> False
    _ if is_free_channel(event.channel) -> True
    _ if is_mentioned -> True
    // Wake on unmentioned: thread root was posted by the bot; thread was
    // @-mentioned earlier; an agent session is active for this thread; the
    // bot authored the root; or the thread PARENT mentions the bot.
    _ -> should_wake_on_unmentioned(event)
  }
}

// ---- Base adapter (guard 1) ------------------------------------------------

pub fn handle_message(event: MessageEvent) -> Nil {
  let identity = canonicalize(event.source)   // RoutingIdentity: transport vs runtime profile
  let key =
    build_session_key(
      event.source,
      group_sessions_per_user: True,     // default: each person in a group gets own session
      thread_sessions_per_user: False,   // default: threads are shared
      profile: identity.runtime_profile,
    )
  case set.contains(active_sessions, key) {
    True ->
      case is_bypass_command(event) {     // /stop /new /approve /deny /queue /status
        True -> runner.handle_inline(event)
        False -> {
          dict.insert(pending_messages, key, event)  // single "next-up" slot, burst collapse
          interrupt_event(key)                       // signal running agent
        }
      }
    False -> spawn(fn() { runner.handle_message(event) })
  }
}

// ---- Runner (guard 2, authorization, turn) ---------------------------------

pub fn runner_handle_message(event: MessageEvent) -> Nil {
  case authorize(event.source) {
    // order: platform allow-all > platform allowlist > DM pairing > global allow-all > deny
    Denied if event.source.chat_type == "dm" -> reply_with_pairing_code(event)
    Denied -> Nil
    Authorized -> {
      let key = session_key_for(event.source)
      case event |> get_command, running_agent(key) {
        Some(cmd), Some(_) -> dispatch_busy_command(cmd, event)   // busy_policy per command
        Some(cmd), None -> dispatch_command(cmd, event)
        None, Some(agent) ->
          case busy_mode(key) {                   // per-session: interrupt | steer | queue
            "interrupt" -> agent.interrupt(event)
            "steer" -> agent.steer(event)         // correction drained at tool boundary
            "queue" -> enqueue_fifo(key, event)   // each /queue gets its own full turn
          }
        None, None -> run_turn(key, event)
      }
    }
  }
}

fn run_turn(key, event) -> Nil {
  let entry = session_store.get_or_create(key)  // only /new or /reset rotate a session
  let context =
    build_session_context_prompt(SessionContext(
      source: event.source,
      home_channels: config.home_channels,
      shared_multi_user_session: is_shared_multi_user(event.source),
    ))
  // multi-user sessions prefix each user message with [sender name]
  let stream = ai_agent.run(entry, context, event)
  // stream-is-the-message adapters: one cumulative native stream per turn,
  // drafts are prefix-stable, consumer declares the final, reconcile by edit
  stream_consumer.deliver(delivery_adapter_for(event.source), stream)
}

pub fn build_session_key(source, group_sessions_per_user, thread_sessions_per_user, profile) {
  // <ns>:<platform>:<chat_type>[:<slack scope>][:<chat_id>][:<thread_id>][:<user>]
  let is_dm = source.chat_type == "dm"
  let isolate_user = case is_dm, source.thread_id {
    True, _ -> source.chat_id == ""
    False, Some(_) -> thread_sessions_per_user
    False, None -> group_sessions_per_user
  }
  [namespace(profile), source.platform, source.chat_type, ..]
  |> append_if(source.scope_id)
  |> append(source.chat_id)
  |> append_ordered(thread: source.thread_id, user: isolate_user)
  |> string.join(":")
}
```

## Platform notes

- **Discord.** `require_mention` default true; **free-response channels** answer without
  mention; **auto-thread** (default on) creates a new Discord thread for every top-level
  @mention so each conversation is isolated; threads are their own session. Optional
  history backfill prepends channel scrollback since the bot's last reply. A short
  "continuation window" accepts unmentioned follow-ups from the same bot (multi-bot relay).
- **WhatsApp** (Baileys bridge or Cloud API). Groups gated by **group policy**
  (`pairing` default = forward nothing, `allowlist` of group JIDs, `open`); optional
  `require_mention` (mention, reply to bot, or `/command`). Quoting a message attaches its
  text (and media, resolved from a local cache) as context.
- **Email, SMS, Matrix, Teams, webhooks** use the same `MessageEvent`; email keys
  conversations on the `From:` address and requires DMARC/SPF/DKIM authentication.

## Distinctive ideas

- **Per-user sessions inside a group by default** (`group_sessions_per_user`), shared
  sessions inside threads. The opposite default from OpenClaw.
- **Two guards** for a busy session, and command **busy policies**.
- **Intake adapter vs delivery adapter**: the bot that received a message is not
  necessarily the bot that answers (profile multiplexing).
- **Home channel** for proactive output; webhook routes with `deliver:` targets
  (including `github_comment`) and per-entity **coalescing**.
