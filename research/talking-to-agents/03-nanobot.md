# nanobot: inbound message pipeline

Source: `HKUDS/nanobot` @ `9f7ae6f` (2026-11-12). Python. Channels publish to an
in-process **message bus**; one **agent loop** consumes it. The smallest of the designs
reviewed, which makes the essential shape easy to see.

Key sources read:
`nanobot/bus/events.py` (`InboundMessage`, `OutboundMessage`), `nanobot/channels/base.py`
(`BaseChannel`, `is_allowed`, pairing), `nanobot/channels/slack/runtime.py`,
`nanobot/channels/discord/runtime.py`, `nanobot/channels/whatsapp/runtime.py`,
`nanobot/channels/email/runtime.py`, `nanobot/channels/linear/runtime.py`,
`nanobot/agent/loop.py` (pending queues, mid-turn injection).

## Shape

```text
channel adapter -> filter (subtype, group policy, mention) -> BaseChannel._handle_message
  -> is_allowed? (star > allowlist > pairing store > deny; pairing code reply)
  -> bus.publish_inbound(InboundMessage)
  -> AgentLoop: session_key -> active turn? inject into pending queue : start turn
  -> OutboundMessage -> bus -> ChannelManager -> channel.send (retry policy)
```

nanobot vocabulary: **channel** = platform adapter; **chat_id**; **sender_id**;
**session key** = `"<channel>:<chat_id>"` unless the adapter overrides it (threads);
**group policy** = `open | mention | allowlist`.

## Pseudocode

```gleam
pub type InboundMessage {
  InboundMessage(
    channel: String,                    // "slack", "discord", "whatsapp", "email", "linear"
    sender_id: String,
    chat_id: String,
    content: String,
    media: List(String),
    metadata: Dict(String, Dynamic),    // platform routing context (thread_ts, message_id ...)
    session_key_override: Option(String),
  )
}

pub fn session_key(msg: InboundMessage) -> String {
  option.unwrap(msg.session_key_override, msg.channel <> ":" <> msg.chat_id)
}

// ---- Slack ------------------------------------------------------------------

pub fn on_slack_event(event) -> Nil {
  use <- bool.guard(event.type_ != "message" && event.type_ != "app_mention", Nil)
  // Only plain user messages and file shares. message_changed, message_deleted,
  // bot_message are all ignored: edits never reach the agent.
  use <- bool.guard(option.is_some(event.subtype) && event.subtype != Some("file_share"), Nil)
  // Slack sends both `message` and `app_mention` for one mention: prefer app_mention
  use <- bool.guard(is_duplicate_of_app_mention(event), Nil)
  use <- bool.guard(
    event.channel_type != "im" && !should_respond_in_channel(event),
    Nil,
  )
  let text = strip_bot_mention(event.text)
  let thread_ts = case event.thread_ts, config.reply_in_thread, event.channel_type {
    Some(t), _, _ -> Some(t)                 // already in a thread (incl. DM threads)
    None, True, ch if ch != "im" -> Some(event.ts) // open a thread on this message
    None, _, _ -> None
  }
  let session_key = option.map(thread_ts, fn(t) { "slack:" <> event.channel <> ":" <> t })
  let content = case first_mention_in_existing_thread(event, thread_ts) {
    True -> prepend_thread_context(event, text)   // "Slack thread context before this mention"
    False -> text
  }
  base.handle_message(sender_id: event.user, chat_id: event.channel, content: content,
    metadata: dict.from_list([#("slack", #(thread_ts, event.channel_type))]),
    session_key: session_key)
}

fn should_respond_in_channel(event) -> Bool {
  case config.group_policy {
    "open" -> True
    "mention" -> event.type_ == "app_mention" || mentions_bot(event.text)
    "allowlist" ->
      list.contains(config.group_allow_from, event.channel)
      && { !config.group_require_mention || mentions_bot(event.text) }
  }
}

// ---- WhatsApp / Discord (abridged) -----------------------------------------

pub fn on_whatsapp_message(m) -> Nil {
  let is_group = m.source.is_group
  // group_policy: "open" (default) | "mention"; mention = @mention or reply to bot
  use <- bool.guard(is_group && config.group_policy == "mention"
    && !{ was_mentioned(m) || is_reply_to_bot(m) }, Nil)
  base.handle_message(sender_id: m.sender, chat_id: m.chat_jid, content: text_of(m),
    metadata: dict.from_list([#("is_group", is_group), #("is_reply_to_bot", is_reply_to_bot(m))]),
    session_key: None)                        // one session per chat
}

pub fn on_discord_message(m) -> Nil {
  // group_policy: "mention" (default) | "open"
  let session_key = case m.channel.is_thread {
    True -> Some("discord:" <> m.channel.parent_id <> ":thread:" <> m.channel.id)
    False -> None
  }
  base.handle_message(..., session_key: session_key)
}

// ---- BaseChannel --------------------------------------------------------------

pub fn handle_message(sender_id, chat_id, content, media, metadata, session_key) -> Nil {
  case is_allowed(sender_id) {        // "*" > allowlist > pairing store > deny
    False -> {
      let code = pairing.generate_code(channel_name, sender_id)
      send(OutboundMessage(chat_id: chat_id, content: format_pairing_reply(code)))
    }
    True ->
      bus.publish_inbound(InboundMessage(channel_name, sender_id, chat_id, content,
        media, metadata, session_key))
  }
}

// ---- AgentLoop -----------------------------------------------------------------

pub fn agent_loop() -> Nil {
  let msg = bus.consume_inbound()
  let key = session_key(msg)
  case dict.get(active_tasks, key), is_command(msg) {
    _, True -> commands.dispatch(msg)            // /stop cancels active tasks for key
    Ok(_turn), False -> queue.put(pending_queue(key), msg)
    // pending messages are drained between model steps and appended as user
    // messages to the running turn (steering by default)
    Error(_), False -> spawn_turn(key, msg)
  }
  agent_loop()
}

fn spawn_turn(key, msg) -> Nil {
  let session = sessions.get_or_create(key)
  let result = run_agent_loop(session, msg, drain_pending: pending_queue(key))
  bus.publish_outbound(OutboundMessage(
    channel: msg.channel, chat_id: msg.chat_id, content: result.text,
    reply_to: dict.get(msg.metadata, "message_id"),
    metadata: msg.metadata,                    // carries thread_ts back to the adapter
  ))
}
```

## Platform notes

- **Slack.** Edits/deletes ignored. Thread replies go to `thread_ts` only when the
  outbound target is the origin chat (a cross-chat send drops the thread).
- **Discord.** Streaming delivered as one message that is progressively edited.
- **WhatsApp.** `group_policy` `open` by default.
- **Email.** `chat_id` = sender address; one session per correspondent, not per thread;
  replies set `In-Reply-To` / `References` and prefix the last subject with `Re:`.
- **Linear.** Consumes Linear's `AgentSessionEvent` webhooks; the platform-native
  agent session id *is* the `chat_id`, and the session key is
  `linear:<organization>:<agent_session_id>`. The parent issue is prepended as context
  once per session.

## Distinctive ideas

- The bus decouples ingest from the loop: inbound and outbound are symmetric envelopes.
- Session identity is just a string the adapter may override; threads are expressed by
  overriding it.
- Mid-turn **injection** is the default busy behaviour.
