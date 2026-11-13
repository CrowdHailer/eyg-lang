# Example chat

A minimal chat app with channels, threads and emoji reactions.
It stands in for Slack or Discord when developing and demonstrating [EYG cloud](../cloud/README.md).
The server uses howdy and the interface is a Lustre live component; there is no custom browser JavaScript.
State is kept in memory and there is no authentication, anyone can post as any name.

```sh
PORT=8080 gleam run
```

Open http://localhost:8080. Add `?channel=links&name=bob` to choose the channel and who you post as.

The HTTP API is documented in [`server.gleam`](./src/example_chat/server.gleam).
Clients poll `GET /api/events?after=<seq>` for posted messages and reactions.
The cloud plugin for this app is described in the [channel plugin guide](../../guides/cloud/channel_plugins.md).

```sh
gleam test
```

The browser regression covers Enter/Shift+Enter composition, threads, reactions and channel switching.
With an isolated app running on port 8188, run from `packages/tracing`:

```sh
EXAMPLE_CHAT_ORIGIN=http://localhost:8188 gleam run -m tracing/example_chat_check
```

Set `CHROME_BIN` when Chromium is installed outside the usual location.
The check saves a screenshot and video under `.recordings`.
