# EYG Cloud

A place to run EYG code away from your local machine

```
(set -a; source .env; set +a; gleam dev)
```

## Sessions

A session is a shell session and/or agent session with persistent state and file system.
External messages get routed to sessions to keep isolation.
We do not yet solve inter session communication.

Each session ID retains its own MFS root and agent history in memory. Slack
sessions are scoped to a workspace/channel and Discord sessions to a guild/channel.

The sessions process loads `policy.eyg` from the working directory at startup.
Direct code, agent tools, and triggers use this policy.

## Secrets

Secrets are per whole workspace.

## Connections

Data sources that are cached/pulled

## Channels

This [article](https://weli.dev/blog/the-valley-of-webhooks/) discusses the reliability problems of webhooks.
Channels are connections that can start a session/chat etc.
Most of their complexity is in solving the problem described in the article

### Slack

With `SLACK_BOT_TOKEN` exported, `gleam run` polls joined public and private channels.
The bot needs `channels:read` and `channels:history` for public channels, and
`groups:read` and `groups:history` for private channels.
New human messages are routed to code execution or the agent as described above.
Replies are posted in the message's thread; posting requires `chat:write`.
Initial history is cached without executing code or starting agent turns.

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

#### Tokens

Discord uses a bot token from the application's **Bot** page in the
[Developer Portal](https://discord.com/developers/applications).
Use the bot token, not the application ID, public key, or OAuth2 client secret.
There is one bot token per application, shared across its server installs.
Resetting it invalidates the previous token.

#### Setup

On the bot page choose "Reset Token" and copy the token.
Enable "Message Content Intent".
enable "Developer Mode" to copy server and channel IDs from the ui.

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

Messages retain the complete Discord object, including attachment metadata and
URLs; attachments are not downloaded. Message IDs (snowflakes) remain strings
to avoid losing precision. Ordering and cursor positions are per channel.

#### Notes

Rate limits return HTTP 429 with a `retry_after` delay in seconds https://discord.com/developers/docs/topics/rate-limits
