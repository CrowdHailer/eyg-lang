# EYG Cloud

A place to run EYG code away from your local machine

## Secrets

## Connections

Data sources that are cached/pulled

## Channels

Connections that can start a session/chat etc

### Slack

#### Tokens

Slack has multiple types of tokens.

App level tokens (`xapp-`) authorize the app accross all organisations and installs.
They are needed to use [socket mode](https://docs.slack.dev/apis/events-api/using-socket-mode)

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

Observed message versions are appended to a single event log per workspace.
The bot discovers which conversations it is part of by polling.
Synchronization re-scans channel history and threads, comparing each message with
its last observed version. Old edits and replies require re-reading old messages;
Slack does not provide a general modification-time cursor.

Only a completed scan can infer that a previously observed message is missing.
Missing messages append a `deleted` event with `reason: "missing"`; explicit
deletion markers use `reason: "tombstone"`. Slack normally omits deleted messages
from history, rather than returning the UI's deleted-message placeholder.
Failures and explicitly limited history must not produce inferred deletions.
Absence can also reflect retention or visibility changes, so inferred deletion
records describe observations, not a confirmed user deletion or its source time.

The log has append order. Source message timestamps, pagination state, and each
trigger's consumption position are separate. Repeated observations are
deduplicated; a missing message that reappears produces another message event.
Polling records observed versions, not every intermediate change between scans.

The [Slack client](../slack/README.md#sans-io-api-client) exposes pure HTTP operations
and a synchronization state machine so the cloud runtime can provide its own
transport, scheduling, and persistence.
