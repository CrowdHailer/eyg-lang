---
name: EYG cloud compared with Hookdeck
description: How EYG cloud and Hookdeck differ, and which to choose.
---

# EYG cloud and Hookdeck

Hookdeck is a hosted event gateway for webhooks. It receives deliveries, queues them, filters, transforms and retries them, and routes them to your endpoints, with a log of every attempt.

| | EYG cloud | Hookdeck |
| --- | --- | --- |
| Role | Acts on events: triggers, agents, posts | Delivers events reliably to the services that act on them |
| Receiving | Webhook, GitHub and Sentry connections with signatures and secrets | Sources for many providers, with signature checks |
| Delivery | Each request runs triggers once, the latest 500 events are kept | Queues, retries, rate limits and replay |
| Logic | Pure EYG patterns and scripts | Filters and JavaScript transformations |

## Human agency

Hookdeck makes webhooks dependable, EYG cloud decides what they mean. They fit together: point a sender at Hookdeck and Hookdeck at a [webhook connection](../connections/webhooks.md), and deliveries are retried until the cloud accepts them.

## Choose Hookdeck when

- You receive high volumes of webhooks and need retries, replay and routing to several services.

## Choose EYG cloud when

- You want to act on webhooks with triggers and agents, under policies you own.
- Use both when deliveries must never be lost.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
