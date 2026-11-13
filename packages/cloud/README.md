# EYG Cloud

A place to run EYG code and agents away from your local machine.
People talk to agents in chat platforms such as Slack or the [example chat app](../example_chat/README.md),
and events from GitHub, Bluesky, RSS feeds, Hacker News and Lobsters run triggers.
Everything a workspace does, which model it uses, what it connects to and what each channel may do, is configured in EYG.

```sh
CLOUD=../../examples/cloud/cloud.eyg gleam run
```

A cloud runs the workspaces listed in `cloud.eyg`, see [`cloud/instance`](./src/cloud/instance.gleam).
People sign in at `/login` to the [web shell](../../guides/cloud/web_shell.md), the first person is the admin.
Everything can be read and changed with the [configuration API](../../guides/cloud/api.md),
from the web shell, from a channel whose shell allows it and over HTTP.
Every program and every effect is [traced](../../guides/cloud/tracing.md) as OpenTelemetry spans.

Start with the [example workspace](../../examples/cloud/README.md).
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
The standard handlers give posted messages to the conversation's agent with who sent them.
The agent is an [overlay](../overlay/README.md) agent, it acts only by running EYG programs.
Nothing the agent replies is shown, it must run a program that performs `Post` to say something in the conversation.
Messages that arrive while the agent is working are given to it together when it finishes.
A session keeps the newest 200 messages, the message `/new` starts a new conversation.

A message that is a single code block tagged `eyg` is a direct invocation, it is run with the channel shell
and its output posted in the message's thread. The agent sees the program and its result with its next message.

## Workspace configuration

`workspace.eyg` evaluates to a record, see [`cloud/config`](./src/cloud/config.gleam).

| Field | |
| --- | --- |
| `llm` | `{provider, model}`, as overlay, i.e. `{provider: Ollama({origin: "https://ollama.com", api_key}), model: "glm-5.3"}` |
| `readme` | Context for every agent in the workspace |
| `files` | Directory, relative to the workspace file, the shared file system starts with |
| `crons` | `[{name, schedule, channel, message}]` messages sent to a channel's session on a schedule |
| `connections` | `[{name, source, channel}]` chats and services, see [connections](../../guides/cloud/connections.md) |
| `channel` | Function from `{platform, id, name}` to `{handle, channel_shell, readme, triggers, llm}`; `handle` and `channel_shell` are required |

The configuration is trusted. It can read the workspace's secrets with the `Secret` effect.
It is evaluated again for each turn, trigger and invocation, so changes apply without a restart.

### Channel shells

A channel shell is the policy for every program run from a channel:
programs people post, programs the channel's agent runs, triggers and their subagents.
It is a complete record with a typed gate for every checked effect. Missing or ill-typed gates are configuration errors.
Gates return `Pass(input)` to perform an effect, `Mock(reply)` to answer without performing it, or `Reject({})` to make it unavailable.
Start with `cloud.reject_all` and overwrite the gates to allow. This platform value is available directly in configuration and programs; the cloud EYG package exports the same complete defaults.

The [cloud EYG package](../../eyg_packages/cloud/) has helpers, `shell.everything`, `shell.offline`, `shell.read_only`
and `shell.writes_under(roots, shell)`, and network secrets in `secrets`.

### Effects

| Effect | Field | |
| --- | --- | --- |
| `Post(text)` | `post` | Post to the conversation |
| `ReadFile`, `WriteFile`, `AppendFile`, `DeleteFile`, `MakeDirectory`, `ReadDirectory`, `CWD` | `read_file` ... | The workspace's shared file system |
| `Fetch`, `Env`, `Now`, `Random`, `Flip`, `Sleep`, `StandardOut`, `StandardError` | `fetch` ... | As on a computer, `Env` returns nothing unless a gate answers it |
| `AddTrigger`, `StopTrigger`, `StartTrigger`, `DeleteTrigger`, `ListTriggers` | `add_trigger` ... | The channel's triggers |
| `Delegate(task)` | `delegate` | Run a subagent with the channel shell, returns its final reply |
| `Events(connection)` | `events` | The logged events of a connection, newest first |
| `Workspaces`, `Connections`, `SetWorkspaceSource`, `SetSecret` ... | `workspaces` ... | The [configuration API](../../guides/cloud/api.md) |
| `Bind({workspace, channel})`, `Unbind({})` | `bind`, `unbind` | Web shells only, run as a channel |
| `Traces(limit)` | `traces` | The most recent [trace spans](../../guides/cloud/tracing.md) |
| `Cron`, `Timeout`, `CancelSchedule` | `cron` ... | Messages sent to the program's session later |
| `Artifact({name, bundle})`, `ShareArtifact(name)` | `artifact`, `share_artifact` | Versioned HTML pages served by the cloud |
| `DecodeJSON`, `Hash` | | Always available |

### Files and skills

A workspace has one shared, content addressed file system built on [`unixfs/mfs`](../unixfs/).
Channel shells decide which paths a channel can change, `shell.writes_under` limits writes to a channel's directories.
Scripts and agent actions resolve imports through the session file system and its `ReadFile` gate, including nested imports and imports inside returned functions. Only trusted configuration imports use the host file system.
Each channel execution discards its lexical scope after returning, matching agent executions.
Skills are `/skills/<name>/SKILL.md` files, agents are given an index of them.
When another channel changes a file an agent has read, including skills, the change is noted with the agent's next message.

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

### Artifacts

`Artifact` saves a version of an HTML bundle and returns its URL.
An artifact belongs to the channel that created it, other channels can save versions once it is shared with `ShareArtifact`.

## Connections

Chats plug into the [channel interface](./src/cloud/channel.gleam), see the [channel plugin guide](../../guides/cloud/channel_plugins.md).
GitHub, Bluesky, RSS, Hacker News and Lobsters only report events, they are not chats, see [connections](../../guides/cloud/connections.md).

This [article](https://weli.dev/blog/the-valley-of-webhooks/) discusses the reliability problems of webhooks.
Channels are connections that can start a session/chat etc.
Most of their complexity is in solving the problem described in the article

### Slack

`{name: "slack", source: Slack({token})}` connects the workspace to Slack with the [Slack plugin](./src/cloud/plugins/slack.gleam),
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

`{name: "discord", source: Discord({token, guild})}` connects the workspace to the server with id `guild` using the [Discord plugin](./src/cloud/plugins/discord.gleam),
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
