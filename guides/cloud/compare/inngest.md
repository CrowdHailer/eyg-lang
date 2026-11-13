---
name: EYG cloud compared with Inngest
description: How EYG cloud and Inngest differ, and which to choose.
---

# EYG cloud and Inngest

Inngest runs durable, event driven functions. Functions written in your application with Inngest's SDKs are triggered by events, schedules or webhooks and run step by step with retries and flow control, in Inngest's cloud or self hosted.

| | EYG cloud | Inngest |
| --- | --- | --- |
| Source | Open source | SDKs open source, the server source available under the SSPL, each version Apache 2.0 after three years |
| Where code lives | Workspace configuration and channel triggers | Your application, served to Inngest |
| Events | Chat, connection and webhook events, matched by pure patterns | Events sent by your code or webhooks, matched by name and expressions |
| Reliability | Triggers run once, failures are traced | Steps are retried and memoised, functions can wait for events |
| Permissions | Effect policies per channel | Your application's code and keys |

## Human agency

Inngest is built for developers making their own services reliable. EYG cloud puts the rules in the hands of the people who use a workspace: triggers are short programs in a channel, and a pattern is a pure function anyone can test.

## Choose Inngest when

- You are building event driven features into your own application and need retries, waits and flow control.

## Choose EYG cloud when

- You want people and agents, not only developers, to add and change automations safely.
- You want the same policy model for chat, agents and triggers.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
