---
name: Writing channel plugins
description: Connect a platform with its native input type and shared channel work.
---

# Writing channel plugins

A plugin publishes a native EYG input type, reports values of that type, and implements operations on its platform.
A configured channel supplies a pure `handle` function that turns those values into work.
The workspace checks handlers and policies. One central session process owns session state and execution; workspaces keep no session registry.

The interfaces are in [cloud/channel](../../packages/cloud/src/cloud/channel.gleam),
the work contract in [cloud/work](../../packages/cloud/src/cloud/work.gleam), and default handlers in
[cloud/handlers.eyg](../../eyg_packages/cloud/handlers.eyg).

## The plugin interface

```gleam
pub type Event {
  Incoming(platform: String, channel: String, reply: Option(String), value: data.Value)
}

pub type Outbound {
  Outbound(
    input_type: binding.Mono,
    post: fn(String, Option(String), String) -> Result(String, String),
    channel_name: fn(String) -> String,
    channels: fn() -> Result(List(#(String, String)), String),
  )
}
```

The event identifies the channel whose handler should run and the native reply destination. Neither is a session handle. The payload remains specific to the plugin.
For example, Slack keeps `ts`, `thread_ts`, `bot_id` and its escaped text;
Discord keeps `content`, the author object, message type and reaction IDs.
There is no common incoming message or participant type.

Expose a public `input_type()` and supply it in `Outbound`.
Construct payloads using [cloud/data](../../packages/cloud/src/cloud/data.gleam).
They must contain plain data, without closures or continuations, because they cross BEAM processes.
See [process boundaries](../../notes/cloud-process-boundaries.md).

Most plugins start with this signature:

```gleam
pub fn start(config: Config, emit: fn(channel.Event) -> Nil) -> Result(channel.Outbound, String)
```

Poll or receive platform events, preserve the fields your schema describes, and call
`emit(channel.Incoming(installation, channel_id, reply, value))`.
`post` returns the platform ID of the message it sent.
`channel_name` supplies the name passed to channel configuration.
`channels` lists the channels available for routing and configuration validation.

## Configure a checked handler

A channel configuration requires both `handle` and `channel_shell`:

```eyg
let cloud = import "../../eyg_packages/cloud/index.eyg"
let channel = (info) -> {
  {
    handle: cloud.handlers.for_channel(info),
    channel_shell: {post: (text) -> { Pass(text) }, ..cloud.reject_all}
  }
}
channel
```

The runtime checks `handle` against the plugin's input type and the shared work result type.
It rejects effectful handlers, access to fields the plugin does not supply, and malformed work results.
Every configured policy is checked against the actual effect interfaces as well.
Uploads validate currently connected channels before replacing the source; newly encountered channels are checked on admission.

Custom handlers can choose different behavior without implementing sessions.
This example chat handler posts the author's name and ignores reactions:

```eyg
match {
  ChatPosted(message) -> {
    [Post({thread: message.thread, text: message.author.name})]
  }
  ChatReacted(_) -> { [] }
}
```

Handlers return a list, processed in order:

| Work | Meaning |
| --- | --- |
| `Input({session, text})` | Give text to the selected session's agent. |
| `Observe({session, text})` | Add context without requesting an agent turn. |
| `Reset(session)` | Forget that session's conversation. |
| `Post({thread, text})` | Post through the channel's checked policy. |
| `Run({session, reply, code, description})` | Run an EYG script with the channel shell, post results to `reply`, and add the result to `session`. |
| `Submit({session, reply, text, description})` | Standard conversation behavior: `/new` resets, a single EYG code block runs, and other text becomes agent input. |
| `Trigger(thread)` | Offer the original native payload to the channel's triggers; their scripts reply in this thread. |

The session selector is `None({})` for the channel's default session or `Some(name)` for a selected session. A name can be a task ID; it need not name a chat thread. The workspace namespaces that selection by workspace, installation and channel, then submits an explicit ID, work and reply callback to the central process. Existing storage paths remain unchanged.
Reply selectors identify native platform destinations. `Input` uses the incoming event's reply destination; `Run`, `Post` and the reset acknowledgement from `Submit` use the explicit reply selector. Changing the reply destination does not change the selected session's files or history. Standard handlers choose thread IDs as session names, but custom handlers can choose independently.
Returning `[]` ignores an event.
The standard handlers suppress the cloud's own messages, format context, and request trigger work.
Custom handlers decide these behaviors explicitly.

Scripts and agent actions resolve imports through the session file system and its `ReadFile` gate.
Only trusted configuration loading resolves host imports.
Each execution starts with explicit inputs and returns a result; channel executions do not retain lexical scope.

## Native schemas

| Plugin | Tags | Payload |
| --- | --- | --- |
| Example chat | `ChatPosted`, `ChatReacted` | Posted messages retain `id, channel, thread, author: {id, name, bot}, text`. Reactions retain `message, by, emoji`. |
| Slack | `SlackMessage`, `SlackReaction` | `channel, thread_ts, message, is_self`; reactions also have `user, reaction`. The message retains the history fields and its full JSON in `data`. |
| Discord | `DiscordMessage`, `DiscordReaction` | `thread, message, is_self`; reactions also have the native `user` object and `emoji` key. Messages retain `id, channel_id, type, author, webhook, content, reactions`. |
| WhatsApp | `WhatsAppMessage` | `message` and optional `referenced` message. A message retains `id, from, name, timestamp, context, data, content`. Content distinguishes text, reactions, buttons, interactive replies and media. |

The authoritative types live beside each implementation:
[example chat](../../packages/cloud/src/cloud/plugins/chat_input.gleam),
[Slack](../../packages/cloud/src/cloud/slack/input.gleam),
[Discord](../../packages/cloud/src/cloud/discord/input.gleam), and
[WhatsApp](../../packages/cloud/src/cloud/plugins/whatsapp.gleam).

Emoji stay native: Slack names, Discord characters or `name:id` keys, and WhatsApp characters.
A handler or trigger may interpret those values for its own purpose.

The example chat polls `GET /api/events?after=<seq>` and skips history on startup.
Slack and Discord keep their existing channel actors and basic session entry points. Configured workspaces attach hooks to those actors; there are no separate Slack/Discord plugin pollers. Native payload types support checked handlers and reaction triggers, rather than defining a second session model.
Slack polls the last hour and follows changed threads.
Discord polls the latest 50 messages in channels and active threads, using snowflake timestamps to skip history.
Discord's outbound operation creates a thread when needed.
These transport choices do not determine how an event is handled.

## Webhooks

Push plugins also return a listener:

```gleam
pub fn start(config, emit) -> Result(#(channel.Outbound, webhook.Listener), String)
```

The workspace registers it at `/connections/<name>/webhook`.
The listener validates deliveries, hands them to the plugin process, and answers promptly.
WhatsApp verifies the subscription token and each delivery's HMAC, deduplicates message IDs, and remembers messages for reaction references.
Each sender is a channel. Its outbound thread selector quotes a message using WhatsApp's reply context.

## Connect the plugin

Add the source to [cloud/connection](../../packages/cloud/src/cloud/connection.gleam) and start it from [cloud/workspace](../../packages/cloud/src/cloud/workspace.gleam).
The workspace's `connections` select which plugins start. Each plugin's `channels` operation lists channel IDs and names so service connections can route events by channel name.

## Testing

Test decoding and polling comparisons with recorded platform payloads.
Check emitted values against the implementation's published `input_type()`, including platform-specific fields.
Then run the plugin with a checked custom handler and a scripted model.
The [plugin tests](../../packages/cloud/test/cloud/plugins/) and
[workspace tests](../../packages/cloud/test/cloud/workspace_test.gleam) cover these boundaries.
