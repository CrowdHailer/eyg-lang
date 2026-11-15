# Webhook and cron setup recording

[`webhook-and-cron.webm`](webhook-and-cron.webm) shows the running Howdy/etui web
terminal creating a box, installing and exercising a webhook, installing a UTC
cron, running it manually, observing an automatic tick, and opening template docs.

The recording uses a disposable local server and demonstration token. It does
not contain production credentials or call a real Slack, Discord, or model account.

Reproduce using `packages/cloud/demo/record.mjs`. The script asserts the resulting
filesystem data, the automatic scheduled execution, and all four documentation
routes. See `packages/cloud/README.md` for setup.
