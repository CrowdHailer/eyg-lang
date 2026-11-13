---
name: EYG cloud compared with Pipedream
description: How EYG cloud and Pipedream differ, and which to choose.
---

# EYG cloud and Pipedream

Pipedream is a hosted integration platform for developers. Workflows start from HTTP requests, schedules or app events, and run steps written in Node.js, Python, Go or Bash alongside prebuilt actions for thousands of apps.

| | EYG cloud | Pipedream |
| --- | --- | --- |
| Hosting | Your own server | Pipedream's cloud |
| Source | Open source | Closed source platform, open source components |
| Triggers | Chats, connections, webhooks, crons | HTTP requests, schedules and app event sources |
| Steps | EYG scripts whose effects are checked | Code steps in several languages and prebuilt actions |
| Permissions | A shell policy per channel, gating every effect | Connected accounts per workflow, workspace roles |
| Agents | An agent in every channel | AI steps and agents built from actions |

## Human agency

Code steps are readable, but what a step can reach is everything its runtime and connected accounts allow, so a reviewer has to read every line. An EYG script can only perform the effects its channel's shell lets through, so the policy is the one place to read what an automation may do.

## Choose Pipedream when

- You need prebuilt integrations with many apps and want steps in a mainstream language.
- You want a hosted service with nothing to run.

## Choose EYG cloud when

- You want automations, agents and people in chat to share one permission model that you own.
- You want to keep the runtime and the data on your own server.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
