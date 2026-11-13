---
name: Connections
description: Connect a workspace to chats and to the services whose events run triggers.
---

# Connections

A workspace's `connections` in `workspace.eyg` list everything it is connected to.
Each connection is `{name, source, channel}`.

```eyg
connections: [
  {name: "chat", source: ExampleChat({origin: "http://localhost:8080"})},
  {name: "slack", source: Slack({token: slack_token})},
  {name: "discord", source: Discord({token: discord_token, guild: "1234567890"})},
  {name: "whatsapp", source: WhatsApp({token: whatsapp_token, phone_number_id: "106540352242922", app_secret: whatsapp_app_secret, verify_token: "choose-a-token"})},
  {name: "github", source: GitHub({repositories: ["owner/repo"], secret: webhook_secret}), channel: "dev"},
  {name: "bsky", source: Bsky({actors: ["gleam.run"]}), channel: "social"},
  {name: "blogs", source: Rss({feeds: ["https://gleam.run/feed.xml"]}), channel: "news"},
  {name: "hn", source: HackerNews({lists: ["top"]}), channel: "news"},
  {name: "lobsters", source: Lobsters({lists: ["newest"]}), channel: "news"}
]
```

Secrets such as tokens come from the workspace's secrets store with the `Secret` effect, see the [cloud README](../../packages/cloud/README.md#secrets).

## Chats and other connections

**Chats**, `ExampleChat`, `Slack`, `Discord` and `WhatsApp`, provide channels.
Every message in a channel reaches the conversation's agent, and a message that is a single `eyg` code block runs with the channel's shell.

**Every other connection** only reports events.
It names a `channel`, its events are logged and given to that channel's triggers, which run with that channel's shell.
Nothing that arrives from these services runs as code: an issue comment containing an `eyg` block is just text in an event.
Agents do not see these events unless a trigger hands them over, for example with `Delegate`.

| Source | Fields | Guide |
| --- | --- | --- |
| `ExampleChat` | `origin` | [example chat](../../packages/example_chat/README.md) |
| `Slack` | `token` | [channel plugins](./channel_plugins.md#slack) |
| `Discord` | `token`, `guild` the server id | [channel plugins](./channel_plugins.md#discord) |
| `WhatsApp` | `token`, `phone_number_id`, `app_secret`, `verify_token` | [channel plugins](./channel_plugins.md#whatsapp) |
| `GitHub` | `repositories`, `secret` optional, `every` seconds, default 60, 0 for webhooks only | [GitHub](./connections/github.md) |
| `Bsky` | `actors`, `feeds`, `every` default 60 | [Bluesky](./connections/bsky.md) |
| `Rss` | `feeds`, `every` default 300 | [RSS](./connections/rss.md) |
| `HackerNews` | `lists`, default `["top"]`, `every` default 120 | [Hacker News and Lobsters](./connections/hacker_news_and_lobsters.md) |
| `Lobsters` | `lists`, default `["newest"]`, `every` default 120 | [Hacker News and Lobsters](./connections/hacker_news_and_lobsters.md) |

The events of each source are listed in [trigger events](./trigger_events.md).
