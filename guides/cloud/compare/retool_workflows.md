---
name: EYG cloud compared with Retool Workflows
description: How EYG cloud and Retool Workflows differ, and which to choose.
---

# EYG cloud and Retool Workflows

Retool Workflows runs automations built from JavaScript or Python code blocks, queries against Retool resources and AI actions, started by schedules or webhooks, in Retool's cloud or self hosted. Workflows run on Temporal.

| | EYG cloud | Retool Workflows |
| --- | --- | --- |
| Hosting | Your own server | Retool's cloud, or self hosted |
| Source | Open source | Closed source |
| Building | EYG code | A visual canvas of code and query blocks |
| Starts work | Chats, connections, webhooks, crons | Schedules and webhooks |
| Permissions | Effect policies per channel | Retool's resource permissions and user groups |

## Human agency

Retool is strong when automations sit next to internal apps that use the same resources. EYG cloud keeps automations as text in the workspace configuration, gated per channel, so the rules are reviewed and changed like code.

## Choose Retool Workflows when

- You already build internal tools in Retool and want automations over the same resources.

## Choose EYG cloud when

- You want automations and agents in chat with policies that are code you own.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
