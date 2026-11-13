# EYG Cloud

A place to run EYG code and agents away from your local machine.
People talk to agents in chat platforms such as Slack or the [example chat app](../example_chat/README.md),
and events from GitHub, Sentry, Bluesky, RSS feeds, Hacker News, Lobsters and any webhook run triggers.
Everything a workspace does, which model it uses, what it connects to and what each channel may do, is configured in EYG.

```sh
CLOUD=../../examples/cloud/cloud.eyg gleam run
```

A cloud runs the workspaces listed in `cloud.eyg`, see [`cloud/instance`](./src/cloud/instance.gleam).
Without a cloud or workspace file, the existing `SLACK_BOT_TOKEN` / `DISCORD_BOT_TOKEN` startup runs the basic agent. It uses the same central session actor and Overlay loop; `CLOUD_DATA` selects its persistent store.
The session process loads `policy.eyg` from the working directory at startup. Direct code and agent tools in basic mode both use it. Configured workspace channels use their checked `channel_shell` policies instead. Ordinary replies and final return values are delivered directly in both modes.
People sign in at `/login` to the [web shell](../../guides/cloud/web_shell.md), the first person is the admin.
Everything can be read and changed with the [configuration API](../../guides/cloud/api.md),
from the web shell, from a channel whose shell allows it and over HTTP.
Every program and every effect is [traced](../../guides/cloud/tracing.md) as OpenTelemetry spans.

Start with the [example workspace](../../examples/cloud/README.md) and the [recordings](../../guides/cloud/recordings/README.md) of it working.
Coming from another agent gateway, see migrating from [OpenClaw](../../guides/cloud/from_openclaw.md) or [Hermes Agent](../../guides/cloud/from_hermes.md).

| Variable | Purpose |
| --- | --- |
| `CLOUD` | The cloud configuration, defaults to `cloud.eyg` |
| `WORKSPACE` | Without a `cloud.eyg`, run this one workspace, defaults to `workspace.eyg` |
| `PORT` / `CLOUD_ORIGIN` | Where the web shell, API, artifacts and webhooks are served, defaults to port 8081 |
| `CLOUD_DATA` | The data directory holding secrets, defaults to `.data` next to the workspace file |
| `EYG_ORIGIN` | The hub packages are loaded from, defaults to `https://eyg.run` |

## How messages are handled

A session is a shell session and/or agent session with persistent state and file system.
External messages get routed to sessions to keep isolation.
We do not yet solve inter session communication.

Every conversation, a channel or a thread in a channel, has a session with an agent.
A checked `handle` function receives each platform's native EYG payload and returns work for sessions, scripts, posting or triggers.
The workspace submits that work with an explicit session ID and a separate reply callback. A handler may select a task session while replying in a different chat thread. Session state lives only in the central process; there are no conversation objects or per-workspace session handles.
The standard handlers give posted messages to the conversation's agent with who sent them.
The agent is an [overlay](../overlay/README.md) agent, it acts only by running EYG programs.
Ordinary agent replies and direct-code return values are delivered to the caller without a policy gate. An explicit `Post` effect still requires the channel policy's permission.
The central actor retains each session's MFS root and history over a shared content-addressed block store. Execution threads updated filesystem state back to that actor; sessions do not start filesystem workers. Snapshots contain only blocks reachable from the session's own root.
One central actor executes all sessions across every workspace, including agent turns, direct invocations, triggers, handler posts and web shell commands. Inputs wait in mailbox order while a program runs. Observations accumulate until the next input for their session. A slow model or program delays all sessions; delegates execute inside the current turn.
A session persists the newest 200 history messages, pending observations and identity metadata. The message `/new` clears history and observations while retaining files and session identity. Every execution starts with fresh lexical scope.

A message that is a single code block tagged `eyg` is a direct invocation, it is run with the channel shell
and its output posted in the message's thread. The agent sees the program and its result with its next message.

## Workspace configuration

`workspace.eyg` evaluates to a record, see [`cloud/config`](./src/cloud/config.gleam).

| Field | |
| --- | --- |
| `llm` | `{provider, model}`, as overlay, i.e. `{provider: Ollama({origin: "https://ollama.com", api_key}), model: "glm-5.3"}` |
| `readme` | Context for every agent in the workspace |
| `files` | Directory, relative to the workspace file, copied into each new session's private file system |
| `crons` | `[{name, schedule, channel, message}]` messages sent to a channel's session on a schedule |
| `connections` | `[{name, source, channel}]` chats and services, see [connections](../../guides/cloud/connections.md) |
| `dataclips` | `[{name, description, shell, clip}]` named functions channels call with `Dataclip`, see [dataclips](../../guides/cloud/dataclips.md) |
| `channel` | Function from `{platform, installation, id, name}` to `{handle, channel_shell, readme, triggers, llm}`; `handle` and `channel_shell` are required |

The configuration is trusted. It can read the workspace's secrets with the `Secret` effect.
It is evaluated again for each turn, trigger and invocation, so changes apply without a restart.
`platform` remains `slack` or `discord`; `installation` includes the Slack team or Discord guild ID. Routing and storage keys include that installation, the workspace name, channel and selected session/thread, so equal channel IDs in different installations do not share state.

### Channel shells

A channel shell is the policy for every program run from a channel:
programs people post, programs the channel's agent runs, triggers and their subagents.
It is a complete record with a typed gate for every checked effect. Missing or ill-typed gates are configuration errors.
Gates return `Pass(input)` to perform an effect, `Mock(reply)` to answer without performing it, or `Reject({})` to make it unavailable.
Start with `cloud.reject_all` and overwrite the gates to allow. This platform value is available directly in configuration and programs; the cloud EYG package exports the same complete defaults.

The [cloud EYG package](../../eyg_packages/cloud/) has helpers, `shell.everything`, `shell.offline`, `shell.read_only`,
`shell.writes_under(roots, shell)` and `shell.with_databases(names, shell)`, and network secrets in `secrets`.

### Effects

| Effect | Field | |
| --- | --- | --- |
| `Post(text)` | `post` | Post to the conversation |
| `ReadFile`, `WriteFile`, `AppendFile`, `DeleteFile`, `MakeDirectory`, `ReadDirectory`, `CWD` | `read_file` ... | The session's private persistent file system |
| `Fetch`, `Env`, `Now`, `Random`, `Flip`, `Sleep`, `StandardOut`, `StandardError` | `fetch` ... | As on a computer, `Env` returns nothing unless a gate answers it |
| `AddTrigger`, `StopTrigger`, `StartTrigger`, `DeleteTrigger`, `ListTriggers` | `add_trigger` ... | The channel's triggers |
| `Delegate(task)` | `delegate` | Run a subagent with the channel shell, returns its final reply |
| `Events(connection)` | `events` | The logged events of a connection, newest first |
| `SQLite({database, sql, parameters})`, `SQLiteQuery({database, query})` | `sqlite`, `sqlite_query` | The workspace's named [databases](../../guides/cloud/dataclips.md), denied by `shell.everything` |
| `Dataclip({name, input})` | `dataclip` | Run a [dataclip](../../guides/cloud/dataclips.md), it runs with its own shell |
| `Workspaces`, `Connections`, `SetWorkspaceSource`, `SetSecret` ... | `workspaces` ... | The [configuration API](../../guides/cloud/api.md) |
| `Bind({workspace, channel})`, `Unbind({})` | `bind`, `unbind` | Web shells only, run as a channel |
| `Traces(limit)` | `traces` | The most recent [trace spans](../../guides/cloud/tracing.md) |
| `Cron`, `Timeout`, `CancelSchedule` | `cron` ... | Messages sent to the program's session later |
| `Artifact({name, bundle})`, `ShareArtifact(name)` | `artifact`, `share_artifact` | Versioned HTML pages served by the cloud |
| `DecodeJSON`, `Hash` | | Always available |

### Files and skills

Each session has a private, content addressed file system built on [`unixfs/mfs`](../unixfs/). The configured seed is copied once; restoring a session never overwrites its files or restores deleted seed files. Sharing files between sessions is deferred.
Channel shells still decide which paths a program can change; `shell.writes_under` limits writes within that session's filesystem.
Scripts and agent actions resolve imports through the session file system and its `ReadFile` gate, including nested imports and imports inside returned functions. Only trusted configuration imports use the host file system.
Each channel execution discards its lexical scope after returning, matching agent executions.
Skills are `/skills/<name>/SKILL.md` files, agents are given an index of them.
Another session's writes cannot change these files or skills. A web user's shell has its own persistent filesystem, shared by that user's commands across bindings. Binding changes the channel policy and outbound destination; it does not grant access to that channel's agent files.

Session snapshots live under `sessions/` in the data directory, with hashed workspace and session identities. File mutations are saved by atomic replacement before success is returned. Invalid snapshots fail to load instead of being silently reset. Keep the data directory on persistent storage and back it up. Snapshots currently retain all content blocks; garbage collection is deferred.
Completed history and observations survive restart. This is not an event log: queued or interrupted executions, dynamic triggers and timers are not recovered, and history updates are not atomic with external effects. Configured triggers and crons are loaded again. File sharing, durable scheduling and replay belong to the event-sourcing work below.

### Triggers

A trigger runs an EYG script when its pattern matches an event in its channel.
A pattern is a pure function from the original native event to a boolean. Events keep tags such as `ChatPosted`, `SlackReaction` and `DiscordMessage`; see the [native schemas](../../guides/cloud/channel_plugins.md#native-schemas).
Patterns that perform an effect fail, the cloud EYG package has `triggers.posted`, `triggers.reaction(emoji)` and `triggers.contains(text)`.
Service connections add events such as `GitHubIssue`, `BskyPost` and `FeedItem`; see [trigger events](../../guides/cloud/trigger_events.md).
The script is a function of the event, it posts to the selected chat thread or the channel for service events.
Triggers come from the channel configuration or the `AddTrigger` effect.

### Schedules

Crons and timeouts send a message to a session, the agent decides whether to post.
Cron schedules have five fields, or six with a leading seconds field, and are evaluated in UTC.

### Secrets

Secrets are stored per workspace with `gleam run -m cloud/secrets`, see [`cloud/secrets`](./src/cloud/secrets.gleam).
Only the workspace configuration can read them.
`secrets.load(name, hosts)` in the cloud EYG package gives channel shells network secrets:
`Env` returns a hash placeholder and `Fetch` to one of the hosts gets the real value.

### Databases and dataclips

A workspace has named SQLite databases in its data directory, used with the same `SQLite` and `SQLiteQuery` effects as the CLI.
Raw access is for trusted channels, other channels call dataclips, named functions with their own shell.
See [dataclips](../../guides/cloud/dataclips.md).

### Artifacts

`Artifact` saves a version of an HTML bundle and returns its URL.
An artifact belongs to the channel that created it, other channels can save versions once it is shared with `ShareArtifact`.

## Connections

Chats plug into the [channel interface](./src/cloud/channel.gleam), see the [channel plugin guide](../../guides/cloud/channel_plugins.md).
GitHub, Sentry, webhooks, Bluesky, RSS, Hacker News and Lobsters only report events, they are not chats, see [connections](../../guides/cloud/connections.md).
[Errors and logs as triggers](../../guides/cloud/errors_and_logs.md) explains acting on Sentry reports and server logs without copying everything into one database.

## Event sourcing

The cloud is to be rebuilt on event sourcing for durable runs and a complete audit record.
[Event sourcing the EYG cloud](../../guides/cloud/event_sourcing/README.md) records the event storming session that designed it, the agreed events and decisions, and the implementation plan.

This [article](https://weli.dev/blog/the-valley-of-webhooks/) discusses the reliability problems of webhooks.
Channels are connections that can start a session/chat etc.
Most of their complexity is in solving the problem described in the article

### Slack

`{name: "slack", source: Slack({token})}` extends the existing [Slack adapter](./src/cloud/slack/channel.gleam) with configured handlers and triggers,
read the token from the secrets store with `perform Secret("SLACK_BOT_TOKEN")`.
The bot needs `channels:read` and `channels:history` for public channels,
`groups:read` and `groups:history` for private channels, and `chat:write` to post.
With the standard handler, messages in a channel the bot is a member of go to that conversation's agent.
A message that is a single code block tagged `eyg` is run with the channel shell instead.
Existing history is not reported when the cloud starts.

#### Tokens

Slack has multiple types of tokens.

App level tokens (`xapp-`) authorize the app accross all organisations and installs.
They are needed to use [socket mode](https://docs.slack.dev/apis/events-api/using-socket-mode)

Configuration token (`xoxe.`) Indicates an expiring access token, with access to read and write apps.

Bot tokens (`xoxb-`) are specific scopes given to an install of the app.
These allow an application to read messages, but only from the channels it is part of.
There is no way to read messages without being added to a channel/group/dm.

#### Setup

To use slack messages as a trigger/channel an [app](https://api.slack.com/apps/) must be created and installed.
A cloud channel is set up with the bot token.
To fetch a bot token the app must have bot token scopes.
If you do not see a "Bot User OAuth Token" check you have created bot token scopes not user token scopes.
Many of the scopes are the same for both bot and user.

A slack trigger is set per conversation and can run any code.
This is separate to the shell/chat access of directly messaging the bot.
shell permissions need to be per channel as well.

#### Storage

All conversations that the bot is part of are streamed into a single event log per workspace.
Ordering and cursor positions are per conversation, that is the only ordering guarantees.
The bot discovers which channels it is part of by polling.

New replies to old threads require separately querying `conversations.replies`. Advancing the channel’s oldest timestamp won’t discover them.
Polling only newer messages misses edits and deletions of older messages.

#### Notes

Cursor-paginated Slack operations return `pagination.Page(payload, next_cursor)`.
https://docs.slack.dev/apis/web-api/pagination/
Not all operations with pagination support this pagination, some use legacy instead.

A slash command triggers an HTTP endpoint.
Editing the slash command message does not rerun the command.

### Discord

*Guilds in Discord represent an isolated collection of users and channels, and are often referred to as “servers” in the UI.

`{name: "discord", source: Discord({token, guild})}` connects the workspace to the server with id `guild` using the existing [Discord adapter](./src/cloud/discord/channel.gleam),
read the token from the secrets store with `perform Secret("DISCORD_BOT_TOKEN")`.
The plugin polls the latest messages of every text and announcement channel and of every active thread.
Messages sent after the cloud started are given to the conversation's agent,
and new reactions on the latest messages are reported to triggers.
A reply to the conversation of a message is posted in a thread started from that message,
Discord gives the thread the message's id.

#### Tokens

Discord uses a bot token from the application's **Bot** page in the
[Developer Portal](https://discord.com/developers/applications).
Use the bot token, not the application ID, public key, or OAuth2 client secret.
There is one bot token per application, shared across its server installs.
Resetting it invalidates the previous token.

#### Setup

On the bot page choose "Reset Token" and copy the token.
Enable "Message Content Intent".
Enable "Developer Mode" to copy server and channel IDs from the ui.
Install the bot with permission to view channels, read message history, send messages,
create public threads and send messages in threads.

Set `DISCORD_BOT_TOKEN` in the local, gitignored `packages/cloud/.env` file.
It is not loaded automatically. From `packages/cloud`, check authentication:

```sh
(set -a; source .env; set +a; gleam dev discord)
```

Set `DISCORD_GUILD_ID` to the server ID and list its text and announcement
channels with:

```sh
(set -a; source .env; set +a; gleam dev discord channels)
```

#### Storage

The plugin keeps the newest message id, reaction counts and reacting users of the latest messages in each channel,
messages themselves live in the workspace's sessions. Attachments are not downloaded.
Message IDs (snowflakes) remain strings to avoid losing precision. Ordering is per channel.

#### Notes

Rate limits return HTTP 429 with a `retry_after` delay in seconds https://discord.com/developers/docs/topics/rate-limits

### WhatsApp

`{name: "whatsapp", source: WhatsApp({token, phone_number_id, app_secret, verify_token})}` connects a WhatsApp business phone number with the [WhatsApp plugin](./src/cloud/plugins/whatsapp.gleam).
WhatsApp pushes messages to the connection's webhook, `<CLOUD_ORIGIN>/connections/whatsapp/webhook`,
which must be reachable over HTTPS, use a tunnel when developing locally.
Each person who messages the number is a channel named by their phone number.

#### Setup

1. Create an app of type "Business" in the [Meta developer dashboard](https://developers.facebook.com/apps/) and add the WhatsApp product.
2. Copy the phone number id from "API Setup", the test number works while developing.
3. Create a system user in Business Settings with the `whatsapp_business_messaging` permission and generate a token,
   save it with `perform SetSecret({name: "WHATSAPP_TOKEN", value: token})`.
4. Copy the app secret from "App settings > Basic" and save it as `WHATSAPP_APP_SECRET`.
5. Under "WhatsApp > Configuration" set the callback URL to the connection's webhook,
   and the verify token to the connection's `verify_token`, Meta checks it with a `GET`.
6. Subscribe the webhook to the `messages` field.

#### Notes

A business can only send free form messages within 24 hours of the person's last message,
outside that window WhatsApp requires an approved template and a post fails with error 131047.
Scheduled messages to quiet conversations can fail for this reason.
