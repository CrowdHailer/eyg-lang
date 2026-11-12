# ElizaOS: inbound message pipeline

Source: `elizaos/eliza` @ `1d5a8983` (2026-11-11). TypeScript agent runtime; platforms are
plugins (`plugins/plugin-discord`, `plugin-slack`, `plugin-telegram`, `plugin-imessage`,
`plugin-x`, ...). There is no WhatsApp plugin in this repository, so the review covers
Discord in detail and Slack by analogy.

Key sources read:
`packages/core/src/types/primitives.ts` (`ChannelType`, `Content`, `MentionContext`),
`packages/core/src/types/environment.ts` (`World`, `Room`, `Participant`),
`packages/core/src/types/memory.ts` (`Memory`),
`packages/core/src/types/message-service.ts` (`IMessageService`, `shouldRespond`),
`plugins/plugin-discord/discord-events.ts`, `plugins/plugin-discord/messages.ts`
(`handleMessageEdit`).

## Shape

```text
discord messageCreate -> MessageManager: allowlist / DM access / pairing
  -> ids: entity (author), room (channel or thread), world (guild)
  -> ensureConnection(entity, room, world)
  -> Memory { entityId, roomId, worldId, content { text, attachments, inReplyTo, source } }
  -> coalesce -> runtime.messageService.handleMessage(memory, callback)
       store memory -> shouldRespond (rules, then model) -> compose state -> plan/actions
       -> callback(content) -> send to Discord (as reply to trigger)
discord messageUpdate -> handleMessageEdit -> supersede the turn
```

Eliza vocabulary: **World** (a server/guild/workspace), **Room** (a channel, DM or
thread, typed by `ChannelType`), **Entity** (any participant, including the agent),
**Participant** (entity in a room), **Memory** (a stored message or fact),
**Content** (text + actions + attachments + `inReplyTo`), **source** (platform name).

`ChannelType = SELF | DM | GROUP | VOICE_DM | VOICE_GROUP | FEED | THREAD | WORLD | FORUM | AUTONOMOUS | API`.

## Pseudocode

```gleam
pub type MentionContext {
  MentionContext(
    is_mention: Bool,   // platform-native mention
    is_reply: Bool,     // reply to the agent's message
    is_thread: Bool,    // in a thread with the agent
  )
}

pub type ResponseDecision {
  ResponseDecision(should_respond: Bool, skip_evaluation: Bool, reason: String)
}

pub fn on_message_create(message: DiscordMessage) -> Nil {
  use <- bool.guard(message.author.id == client.user.id, Nil)
  use <- bool.guard(!channel_allowed(message.channel_id), Nil)
  use <- bool.guard(is_dm(message) && !dm_access_allowed(message.author), Nil) // pairing
  let entity_id = unique_uuid(agent, message.author.id)
  let room_id = unique_uuid(agent, message.channel.id)       // a thread is its own room
  let world_id = unique_uuid(agent, option.unwrap(message.guild_id, message.channel.id))
  ensure_connection(entity_id, room_id, world_id,
    room_type: case message.channel { Dm -> DM  Thread -> THREAD  _ -> GROUP })
  let memory =
    Memory(
      id: unique_uuid(agent, message.id),
      entity_id: entity_id,
      room_id: room_id,
      world_id: world_id,
      content: Content(
        text: message.content,
        attachments: process_attachments(message),
        in_reply_to: option.map(message.reference, fn(r) { unique_uuid(agent, r.message_id) }),
        source: "discord",
      ),
    )
  let mention = MentionContext(
    is_mention: mentions_agent(message),
    is_reply: replies_to_agent(message),
    is_thread: message.channel.is_thread,
  )
  coalesce(room_id, memory, fn(batch) { handle(batch, mention) })
}

fn handle(memory, mention) -> Nil {
  let result =
    message_service.handle_message(runtime, memory, callback: fn(content) {
      discord.send(memory.room_id, content, reply_to: memory.id)
    })
  result
}

// core: DefaultMessageService
pub fn handle_message(runtime, memory, callback) -> ProcessingResult {
  runtime.create_memory(memory, table: "messages")
  let room = runtime.get_room(memory.room_id)
  let decision = should_respond(runtime, memory, room, mention_context(memory))
  case decision.should_respond {
    False -> ProcessingResult(did_respond: False, ..)
    True -> {
      let state = runtime.compose_state(memory)      // providers: recent messages, facts, entities
      let response = planner.run(state)              // actions, reply text
      list.each(response.messages, callback)
      evaluators.run(memory, response)               // reflection, fact extraction
    }
  }
}

pub fn should_respond(runtime, memory, room, mention) -> ResponseDecision {
  case room.type_, mention {
    DM, _ | API, _ -> ResponseDecision(True, True, "direct")
    _, MentionContext(is_mention: True, ..) -> ResponseDecision(True, True, "mention")
    _, MentionContext(is_reply: True, ..) -> ResponseDecision(True, True, "reply")
    // ambiguous group chatter: ask a (small) model whether to respond, ignore, or stop
    _, _ -> ask_should_respond_model(runtime, memory, room)
  }
}

// ---- Edits ---------------------------------------------------------------------

pub fn on_message_update(update) -> Nil {
  use <- bool.guard(option.is_none(update.edited_timestamp), Nil) // unfurls, pins
  use <- bool.guard(update.author.is_bot, Nil)  // bots edit to stream, not to correct
  case running_turn(update.id) {
    // A turn that has not visibly started (no typing yet) would answer text the
    // user replaced: abort it; the edit's turn gives the only answer.
    Some(turn) if !turn.typing && newer(update.edited_at, turn.edited_at) ->
      abort(turn, "superseded by an edit")
    _ -> Nil
  }
  // re-run only for messages the agent actually took in, and only newer revisions
  queue_message_turn(update.id, fn() { reprocess_with_edited_content(update) })
}
```

## Distinctive ideas

- **World / Room / Entity**: a small, platform-neutral spatial vocabulary; agents are
  entities too, so multi-agent rooms need no special case.
- **shouldRespond** as an explicit decision with a reason, falling back to a model for
  ambiguous group messages (engagement by judgement, not only by rule).
- **Edit supersedes** an un-started turn, then re-runs; an already-visible turn finishes.
- Messages are **memories**: the transcript and long-term memory share one store.
