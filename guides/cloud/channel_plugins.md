---
name: Configured chat adapters
description: How chat adapters send native events to checked workspace handlers after deployment.
---

Configured adapters land after the deployment checkpoint. Main's basic Slack and
Discord adapters and startup triggers remain available before that stage.

The [example chat adapter](../../packages/cloud/src/cloud/plugins/example_chat.gleam)
polls the standalone chat application. The
[WhatsApp adapter](../../packages/cloud/src/cloud/plugins/whatsapp.gleam) receives
signed deliveries through its registered webhook listener. Both supply native
payloads, an input type and outbound channel operations.

`channel.Incoming` carries the installation, channel identity and native value.
The workspace checks `on_input` against that adapter's type before running it.
Its returned work selects a session and an independent reply target. Programs,
triggers and agent turns execute through the central session actor; adapters do
not own session files or write local stores.

Slack and Discord extensions later attach hooks to main's adapters, retaining
their checked startup triggers. Installation-qualified identities prevent equal
channel IDs in different teams from sharing state or outbound routes.

There is no public default-handler helper package. A workspace defines its own
`on_input` callback, returning the work supported by
[`cloud/work`](../../packages/cloud/src/cloud/work.gleam). Tests use small local
fixtures to exercise the host contract.
