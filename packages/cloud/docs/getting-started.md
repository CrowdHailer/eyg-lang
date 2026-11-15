# Getting started

From packages/cloud, with Gleam and Erlang installed:

    export EYG_CLOUD_TOKEN='choose-a-long-random-administrator-token'
    gleam run -m cloud/web

Open http://127.0.0.1:8787. The token must contain at least 24 characters. Data is
stored in .cloud by default; set EYG_CLOUD_DATA to an absolute persistent directory.
PORT changes the port; EYG_CLOUD_BIND changes the listening address. Use HTTPS
and a WebSocket-capable reverse proxy when publishing the dashboard.

## Create a computer

1. Enter your administrator token and choose Connect.
2. In Boxes, enter a lowercase name and choose one of the 20 initial filesystems.
3. Choose Create box. The summary displays its root and file count.
4. Select Files to browse code, policies and data.

## Set up a webhook

1. Create a box named demo using the Webhook inbox template.
2. Open Automation and choose Install webhook. This installs an HTTP handler
   that appends request bodies to /data/webhooks.ndjson.
3. Enter a payload and choose Send test webhook.
4. In Files, open /data/webhooks.ndjson to inspect the result.

Send an actual request from another application:

    curl -X POST http://127.0.0.1:8787/app/demo/hook \
      --data-binary '{"event":"hello"}'

The application endpoint is public. Implement signature verification in the
handler when connecting a webhook provider. The management API requires a token.

## Set up a cron

1. In Automation, name a cron heartbeat and enter * * * * * (every minute, UTC).
2. Choose Install cron, then Run cron now to verify the handler immediately.
3. Open /data/cron.log in Files. The automatic scheduler appends another entry
   at the next minute boundary. Refresh to see new roots and execution traces.
4. Edit /system/cron/heartbeat.eyg to change the handler or schedule. Stage the
   file, then Commit batch. Invalid schedules are rejected before activation.

## Edit atomically

Select a file, edit its contents and choose Stage file. Stage other dependent
files before choosing Commit batch. If a cron or request has changed the root,
the commit reports a conflict. Inspect the changes and refresh the root before
resubmitting your draft. A failed validation leaves the previous application live.

## Give an external agent access

In Tokens, create a policy for the selected box:

    (request) -> {
      !string_starts_with(request.path, "/data/")
    }

Copy the generated token once. Use Authorization: Bearer TOKEN for API calls.
The dashboard also displays its ID for revocation. Policy code is account-owned:
an agent cannot grant itself more access by editing the box.

## Connect a shell or agent

The Shell / agent panel sends input through /system/connection.eyg. Templates
start in shell mode: enter !int_add(2, 3) to evaluate code. Change its mode field
to "agent" to send prompts to Overlay instead. OLLAMA_API_KEY selects the hosted
provider; without it the server uses local Ollama. The connection's policy is
checked on every invocation. Complete agent trajectories, including tool calls
and results, are saved under /traces/sessions using the authenticated identity.

## Connect Slack or Discord

Configure SLACK_BOT_TOKEN on the server, or DISCORD_BOT_TOKEN and DISCORD_GUILD_ID.
Restart the server to start the existing polling transports. In Automation,
select the platform, enter workspace/guild and channel IDs, and choose Install
channel agent. This installs a per-channel policy and an agent connection.

The agent may write /slack/channel/CHANNEL/ (or /discord/channel/CHANNEL/), read
that directory and /app/skills/, and cannot read secrets or make network requests.
The model transport itself is configured by the host. Add skills through Files.
The bridge lowercases identifiers in configuration paths. A channel connection
is /system/connections/slack-WORKSPACE-CHANNEL.eyg or its discord equivalent.

To handle every incoming event with EYG, create
/system/events/slack-WORKSPACE-CHANNEL.eyg containing {handler, policy}. The
handler receives {channel_name, event: MessageCreate({ts, channel_id, content,
thread_ts})} and returns {}. Discord's MessageCreate has {id, channel_id, content}.
Initial polling history is loaded without replaying it. Existing transport
limitations on edited messages and old thread replies still apply.

## Publish a subdomain

Route *.eyg.cloud to this service, preserve Host and enable TLS at your proxy.
The box demo serves demo.eyg.cloud. Set EYG_CLOUD_DOMAIN for a different suffix.
For local testing, /app/demo/ provides the same handler without DNS changes.

## Snapshots

The API returns root history. Fork any recorded root through the fork endpoint,
or fork the current root with the Files panel. The new box evolves independently.
The current store is intentionally simple: one JSON snapshot per box retains its
content blocks and root history. Back up the data directory and account.json.
