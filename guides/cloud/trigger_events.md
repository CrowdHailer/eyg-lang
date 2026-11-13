---
name: Trigger events
description: Every event a trigger's pattern and script receive, by connection.
---

# Trigger events

A trigger is `{name, pattern, script}` installed in a channel.
Its pattern is a pure function from an event to `True({})` or `False({})`, it cannot perform effects.
When the pattern returns `True({})` the script, a function of the same event, runs with the channel's shell.
A script may also be EYG source text with the event in scope as `event`.

Events are tagged by kind, so patterns and scripts `match` on the tag:

```eyg
let pattern = match {
  GitHubIssue(issue) -> { !equal(issue.action, "opened") }
  | (_) -> { False({}) }
}
```

A channel's triggers receive the events of its chat and of every connection whose `channel` names it,
see [connections](./connections.md).
The cloud EYG package has common patterns in `cloud.triggers`: `posted`, `reaction(emoji)`, `contains(text)`,
`issue_opened`, `pull_request_merged` and `title_contains(text)`.

The type of every event is written in Gleam in [`cloud/trigger.event_type`](../../packages/cloud/src/cloud/trigger.gleam),
it is also the type of the values the `Events` effect returns.

## Chat

A channel's `handle` function returns `Trigger(thread)` to offer its original plugin payload to triggers.
The chosen thread determines where trigger scripts post.
The standard handlers request this for incoming messages and reactions.

| Event | Fields |
| --- | --- |
| `ChatPosted` | `id, channel, thread, author: {id, name, bot}, text` |
| `ChatReacted` | `message` in the example chat shape, `by: {id, name, bot}, emoji` |
| `SlackMessage` | `channel, thread_ts, message, is_self`; message fields include `ts, user, bot_id, text, reactions` |
| `SlackReaction` | Slack message fields above, plus `reaction, user` |
| `DiscordMessage` | `thread, message, is_self`; message fields include `id, channel_id, type, author, content, reactions` |
| `DiscordReaction` | Discord message fields above, plus `emoji, user` |
| `WhatsAppMessage` | `message: {id, from, name, timestamp, context, data, content}`, `referenced: Option(message)` |

See the [plugin guide](./channel_plugins.md#native-schemas) for the complete type definitions.
Emoji stay in the platform's format: `books` on Slack, `📚` on WhatsApp, and a character or `name:id` on Discord.
`cloud.triggers.reaction(emoji)` compares that exact value.
Scripts match the platform tag to access its fields; there is no shared incoming message shape.

## GitHub

Every GitHub event has `connection`, `repository` (`owner/name`), `actor` (the login that caused it) and `url`.
Scripts post at the top of the channel.

| Event | Extra fields | From |
| --- | --- | --- |
| `GitHubIssue` | `action`, `number`, `title`, `body`, `labels` | `issues` |
| `GitHubComment` | `action`, `number`, `title` of the issue, `body` of the comment | `issue_comment` |
| `GitHubPullRequest` | `action`, `number`, `title`, `body`, `merged`, `branch`, `base` | `pull_request` |
| `GitHubPush` | `branch`, `commits: [{id, message, author}]` | `push` |
| `GitHubStar` | | `star`, `watch` |
| `GitHubFork` | `fork` | `fork` |
| `GitHubRelease` | `action`, `tag`, `name`, `body` | `release` |
| `GitHubWorkflowRun` | `name`, `conclusion`, `branch` | `workflow_run`, webhooks only |
| `GitHubEvent` | `type` | anything else |

`action` is GitHub's, for example `opened`, `closed` or `reopened`.
A merged pull request is `action: "closed"` with `merged: True({})`.
The events API omits push commits for most repositories, use webhooks when they matter.

## Bluesky

| Event | Fields |
| --- | --- |
| `BskyPost` | `connection`, `uri`, `url`, `author` (display name), `account` (handle, e.g. `gleam.run`), `text`, `created_at`, `reply`, `likes`, `reposts`, `replies`, `source` |

`source` is `@account` for posts by a followed account or the feed's `at://` URI.
Counts are as they were when the post was first seen.

## RSS and Atom

| Event | Fields |
| --- | --- |
| `FeedItem` | `connection`, `feed` (the feed url), `id`, `title`, `link`, `summary`, `published` |

`summary` is the item's description, summary or content, it may contain HTML.
`published` is the date as the feed writes it.

## Hacker News

| Event | Fields |
| --- | --- |
| `HackerNewsStory` | `connection`, `list`, `id`, `title`, `url`, `link`, `by`, `score`, `comments` |

`link` is the discussion page, `url` the story's link, or the discussion page for Ask HN posts.

## Lobsters

| Event | Fields |
| --- | --- |
| `LobstersStory` | `connection`, `list`, `id`, `title`, `url`, `link`, `tags`, `submitter`, `score`, `comments` |

## Which events run triggers

Connections that poll log what they find on their first poll without running triggers,
so starting the cloud does not replay old activity. Later events are live and run triggers.
Every event is kept in the connection's log, the latest 500, and programs read it with `Events`:

```eyg
match perform Events("hn") {
  Ok(events) -> { !list_fold(events, 0, (_event, count) -> { !int_add(count, 1) }) }
  Error(reason) -> { 0 }
}
```

`Events` takes a connection's name and returns its events newest first.
Like every effect it is only available when the channel shell has an `events` gate.
