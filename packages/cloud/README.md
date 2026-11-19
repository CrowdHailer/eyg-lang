# EYG Cloud

A place to run EYG code away from your local machine

```
(set -a; source .env; set +a; gleam dev)
```

## Boxes

A box is a file system with an id.
A box with a name is shared, a box without one is transient and only reached through its id.
Each change is recorded as an event with the new file system root, so a box is the chain of its roots.
A box only moves to a root where every `.eyg` file type checks, imports are resolved in the same file system.

Events are stored in Postgres and the blocks of the file system in S3, under their content identifier.
A new box is only kept in memory until a session is made in it, then its events are stored in Postgres.
A box no session was made in is lost when the service stops.

### API

The API is started when `POSTGRES_HOST` is set.
There are no accounts yet. It only accepts local connections unless `ACCESS_PASSWORD` is set,
then it accepts every connection and every request needs the password, with HTTP basic authentication and any user name.

| Request | |
| --- | --- |
| `GET /boxes` | The named boxes. |
| `POST /boxes` | Create a box from `{"name": "home"}`, leave out the name for a transient box. Add `"from": id` to start at the root of another box. |
| `GET /boxes/:id` | The name, latest sequence and root of the box. |
| `GET /boxes/:id/files/*path` | The contents of a file or the entries of a directory. |
| `PUT /boxes/:id/files/*path` | Write the request body to a file. Missing directories are created. |
| `DELETE /boxes/:id/files/*path` | Delete a file or directory. |
| `GET /boxes/:id/secrets` | The names of the box's secrets. |
| `PUT /boxes/:id/secrets/:name` | Set a secret to the request body. |
| `DELETE /boxes/:id/secrets/:name` | Remove a secret. |

A new box starts with the files in `priv/box`, a skill in `/skills/writing-skills/SKILL.md` on writing skills.
Agents chatting in a box are told to look for skills in `/skills` at the start of a task.

Code in a box reads the box's secrets with the `Env` effect, a clone starts with a copy of them.

A change that leaves an invalid module is rejected with status 422 and the box is not changed.
Status 409 is returned when the name is taken, or a file changed by something else first.
Changes are made away from the box and merged by the box's one process, which rejects files changed on both sides.

### Sessions API

A session runs EYG code in a box and records each turn so it can be read back later.
Many sessions can use the same box, they all see the latest files.
A session in a transient box, cloned from a named box, works on its own copy of the files.

| Request | |
| --- | --- |
| `POST /boxes/:id/sessions` | Start a session in the box, send `{"llm": name}` for a session that chats with an llm. |
| `GET /boxes/:id/sessions` | The sessions in the box. |
| `GET /sessions/:id` | The session and all of its turns. |
| `POST /sessions/:id/turns` | Run the code from `{"code": "1"}` or a program as DAG-JSON from `{"program": program}`, or reply to `{"message": "hi"}` in a chat. |
| `GET /sessions/:id/events` | Every event of the session as JSON lines. |
| `POST /sessions/:id/fork` | Start a session with the same history, each continues from it on its own. |
| `GET /sessions/:id/trace` | OpenTelemetry spans for the session, each turn and each request, as OTLP JSON. |
| `GET /llms` | The names of the llms a session can chat with. |

Posting exported events, as JSON lines with content type `application/x-ndjson`, to `POST /boxes/:id/sessions` creates a session from them.
The events are only accepted if replaying every turn does what they say.
A copy of a session with an unfinished turn finishes that turn when it is next used.

Traces are made from the session events, so there is no separate instrumentation.
The OTLP JSON can be posted to the `/v1/traces` endpoint of any OpenTelemetry collector.

A turn returns its `output` and either a `value` or an `error`.
File changes are only kept if the code succeeds and the box accepts them, i.e. all modules type check.
Code runs in the session's own process. Before each request or sleep, and at the end, its events are recorded and then its file changes are merged into the box.
A turn that only reads files never waits for other sessions.

A chat runs the code of each tool call the llm makes, as an Overlay agent does, and replies with the llm's answer.
There are no accounts yet, so every configured llm is available to every session.

Sessions are durable, every turn is recorded as events that are enough to resume it.
Events are stored in an append only thread and a session points at the last event of its history.
If the process running a turn stops, the turn is finished the next time code is sent to the session.
See `cloud/sessions/turn.gleam` for how a turn is recorded and replayed.

### Web interface

The web interface is started with the API on `WEB_PORT`, by default 8787, with the same access as the API.
It is a terminal in the page that lists the named boxes and creates new ones.
A box is opened by starting a shell or a chat in it, or in a transient copy of it, or by managing its secrets.
The terminal fills the window and a session fills it from the bottom, as a terminal does.
The log scrolls back with page up and page down or the mouse wheel, a reply longer than the screen is shown from its start.
A shell's programs are written as EYG text, which can be pasted, or with the structural editor and the same keys as the EYG shell.
Variables, builtins, packages and files are chosen in a box in the middle of the screen, which shows each with its type.
In a shell, up with nothing written selects code run before, as in the EYG shell, and enter writes it in the draft to edit and run again.
Tab switches between them and keeps both, shift and enter starts a new line in text and in chat messages.
Text is edited with arrows, home and end, ctrl or alt with an arrow moves by word, program text is highlighted.
A wide window shows the files of the box beside the session, and a running turn shows what it has done so far.
The llm's thinking and reply are shown as they arrive. Only the latest thinking is shown in full, earlier thinking is a line saying how long it was.
Messages written while a chat runs are added to the chat once the tool calls running finish,
or start the next turn if the llm has replied. Ctrl+x cancels a running turn.
Shortcuts with ctrl or meta and function keys are left to the browser, so output can be copied and F11 goes full screen.
A web page or image that a turn writes is shown beside the session, or over most of a narrow screen.
Files the session changed are coloured in the files beside it, clicking any file shows it.
A page is read from `/artifacts/:root/*path` by the root of the box's files, so it links to the files beside it,
and runs in a sandbox with its own origin, so its scripts cannot use the terminal or the API.
Recent sessions, and any session by its id, are opened again with their history.
Sessions in transient boxes are only listed after pressing `t`.
A turn that did not finish is finished when its session is opened, a running turn can be cancelled.

### Configuration

```sh
# the database, or DATABASE_URL=postgres://user:password@host:port/database
POSTGRES_HOST=localhost
POSTGRES_PASSWORD=postgres
# the bucket blocks are kept in, such as Railway's blob storage or any S3 compatible store
S3_ENDPOINT=https://s3.eu-west-1.amazonaws.com
S3_REGION=eu-west-1
S3_BUCKET=
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=
# optional, the llm sessions chat with is Ollama's cloud, without a key there is none
OLLAMA_API_KEY=
# optional, without it only local connections are accepted
ACCESS_PASSWORD=
# optional, default to 8080 and 8787
PORT=8080
WEB_PORT=8787
```

Migrations are applied when the service starts.

### Deploying

`Dockerfile` builds the service, from the root of the repository as it depends on other packages by path.
`railway.json` at the root of the repository deploys it to Railway with that Dockerfile.
`GET /health` on the API does not need the password, it is for the host's health checks.

```sh
docker build -f packages/cloud/Dockerfile .
```

### Database

Tests need a Postgres database with the migrations applied.
The `.env` file needs `POSTGRES_HOST` and `POSTGRES_PASSWORD`.

```sh
(set -a; source .env; set +a; gleam dev migrate)
(set -a; source .env; set +a; gleam test)
```

## Sessions

A session is a shell session and/or agent session with persistent state and file system.
External messages get routed to sessions to keep isolation.
We do not yet solve inter session communication.

Discord channels have durable sessions in a box, the same sessions as the API and web interface.
Each channel is bound to one session and the binding is kept in Postgres, so a conversation continues after a restart.
Slack sessions and triggers still keep their own MFS root and agent history in memory, scoped to a workspace/channel.

The sessions process loads `policy.eyg` from the working directory at startup.
Direct code, agent tools, and triggers use this policy.

## Crons

A named box runs code on a schedule from its configuration, the `/_box/config.eyg` module,
so crons are made and changed by writing that file in a session and the box only accepts them if they type check.
Each field of `crons` is a cron, with a `schedule` in cron syntax in UTC and a `run` function called with an empty record.

```eyg
{crons: {hacker_news: {schedule: "7 8 * * *", run: import "../hn.eyg"}}}
```

New boxes start with a configuration without crons.
Each cron runs as a turn in its own session in the box, so its runs are in that session's history.
A cron first runs the next time its schedule matches, a run missed while the service was stopped runs once when it starts again.
The next run of each cron is kept in Postgres and claimed before it runs, so each runs once.
Transient boxes have no crons. See `cloud/crons.gleam`.

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

Discord also needs the database, and `DISCORD_BOX` set to the name of the box its channels have sessions in.
Set `DISCORD_CHANNELS` to a comma separated list of channel names to only serve those channels.
A message to the bot goes to the session's llm, fenced code runs in the box.
The scheduled check-in to a `#noise` channel is a demo, it only runs when `DISCORD_NOISE` is set.

#### Storage

Messages retain the complete Discord object, including attachment metadata and
URLs; attachments are not downloaded. Message IDs (snowflakes) remain strings
to avoid losing precision. Ordering and cursor positions are per channel.

#### Notes

Rate limits return HTTP 429 with a `retry_after` delay in seconds https://discord.com/developers/docs/topics/rate-limits
