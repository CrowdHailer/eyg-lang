# Vercel Chat SDK: inbound message pipeline

Source: `vercel/chat` @ `d0ff1dc` (2026-11-12). TypeScript library, not an agent: it is
the cross-platform abstraction other projects build on (NanoClaw bridges to it). It is
included because it is the most deliberate attempt at a shared vocabulary, and its
adapters cover Slack, Discord, WhatsApp, Teams, Google Chat, Telegram, GitHub, GitLab,
Linear, Gmail, Notion and more.

Key sources read:
`apps/docs/content/docs/{threads-messages-channels,handling-events,concurrency,subject}.mdx`,
`packages/adapter-github/README.md`, `packages/adapter-gmail/README.md`,
`packages/chat/src/types.ts`.

## Shape

```text
webhook -> adapter.parse -> Chat.process
  -> self message? drop -> dedupe -> thread lock (concurrency strategy)
  -> route: DM handler > subscribed-thread handler > new-mention handler > pattern handlers
  -> user handler(thread, message, context) -> thread.post / stream / subscribe
edits, deletes, reactions, actions, slash commands, modals: separate lifecycle handlers
```

Chat SDK vocabulary: **Chat** (the bot), **adapter** (platform), **Channel** contains
**Thread**s, a Thread contains **Message**s; every conversation, even a DM, is a Thread.
**Author**, **subscription** (thread-level opt-in), **Subject** (the issue/PR/page a
comment is about), **state adapter** (persistence).

## Pseudocode

```gleam
pub type Message {
  Message(
    id: String,
    thread_id: String,      // "slack:C123:1700000000.123" | "github:owner/repo:issue:42"
    author: Author,         // user_id, user_name, full_name, is_bot, is_me
    text: String,
    formatted: Mdast,       // platform-neutral markdown AST
    attachments: List(Attachment),
    is_mention: Bool,
    metadata: MessageMetadata, // date_sent, edited, edited_at
  )
}

pub type Concurrency {
  Drop                      // default: busy thread discards new message (LockError)
  Queue                     // run latest queued message; earlier ones in context.skipped
  Burst(debounce_ms: Int)   // wait, then drain the burst like Queue
  Debounce(debounce_ms: Int)// latest message replaces earlier ones
  Concurrent                // no lock
}

pub fn process(adapter: Adapter, request: Request) -> Response {
  let event = adapter.parse_webhook(request)
  case event {
    MessageCreated(message) -> process_message(adapter, message)
    // Lifecycle events: never routed to message handlers; concurrency not applied.
    // Bot's own edits are filtered (post+edit streaming would echo).
    MessageUpdated(message, previous) -> run(on_message_updated, thread_of(message), message, previous)
    MessageDeleted(e) -> run(on_message_deleted, e)
    ReactionAdded(r) | ReactionRemoved(r) -> run(on_reaction, r)
    Action(a) -> run(on_action, a)           // button clicks on cards
    SlashCommand(c) -> run(on_slash_command, c)
    ModalSubmit(m) -> run(on_modal_submit, m)
    AgentSessionStopped(e) -> { abort(thread_signal(e.thread_id)) run(on_agent_session_stopped, e) }
  }
}

fn process_message(adapter, message) -> Response {
  use <- bool.guard(message.author.is_me, ack())     // never sees its own messages
  use <- bool.guard(state.dedupe_seen(message.id), ack())
  let thread = Thread(id: message.thread_id, adapter: adapter)
  use context <- with_thread_lock(thread, config.concurrency)  // may drop/queue/burst
  let subscribed = state.is_subscribed(thread.id)
  case thread.is_dm, subscribed, message.is_mention {
    True, _, _ if has_handlers(on_direct_message) ->
      run(on_direct_message, thread, message, context)
    _, True, _ -> run(on_subscribed_message, thread, message, context)
    _, False, True -> run(on_new_mention, thread, message, context)
    True, False, _ -> run(on_new_mention, thread, message, context) // DM counts as mention
    _, False, False ->
      list.each(pattern_handlers, fn(h) {
        case h.pattern {
          None -> h.run(thread, message)
          Some(re) if regex.check(re, message.text) -> h.run(thread, message)
          _ -> Nil
        }
      })
  }
}

// ---- What an agent built on it looks like -----------------------------------

pub fn main() {
  let bot = chat.new(adapters: [slack(), discord(), whatsapp(), github()],
    state: redis_state(), concurrency: Burst(1000))

  chat.on_new_mention(bot, fn(thread, message, _ctx) {
    thread.subscribe(thread)                  // future messages -> on_subscribed_message
    thread.start_typing(thread)
    let history = thread.all_messages(thread) |> to_ai_messages
    thread.post(thread, generate(history))    // or post a stream: post + edit
  })

  chat.on_subscribed_message(bot, fn(thread, message, ctx) {
    let turn = list.append(ctx.skipped, [message])   // burst / queue drained messages
    thread.post(thread, generate(turn))
  })
}
```

## Thread id formats (identity of a conversation)

| Platform | Thread id |
|---|---|
| Slack | `slack:<channel>:<thread_ts>` |
| GitHub PR conversation | `github:<owner>/<repo>:<pr>` |
| GitHub review comment thread | `github:<owner>/<repo>:<pr>:rc:<comment_id>` |
| GitHub issue | `github:<owner>/<repo>:issue:<n>` |
| Gmail | Gmail's native thread id; replies target Reply-To, else From |

## Distinctive ideas

- **Thread is the unit**: a DM is a thread, a GitHub issue is a thread, an email thread
  is a thread. The Channel is the container.
- **Subscription** replaces most mention-gating rules: mention starts, subscribe keeps.
- **Subject**: comments on issues/PRs/pages resolve the parent resource lazily.
- **Edits and deletes are lifecycle events**, deliberately outside conversational routing
  (and today only the Slack adapter emits them).
- A **feature matrix** per adapter (typing, edits, reactions, ephemeral, modals, read
  receipts) with no-op or `NotImplementedError` fallbacks.
- **Email specifics** in the Gmail adapter: no edit or retract, streaming buffers then
  sends once, "ephemeral" falls back to a private email in the same thread, channel
  visibility is `unknown`, `From:` is not proof of identity.
