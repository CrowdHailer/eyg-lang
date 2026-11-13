---
name: EYG cloud compared with Vercel Chat SDK
description: How EYG cloud and Vercel Chat SDK differ, and which to choose.
---

# EYG cloud and Vercel Chat SDK

Chat SDK is a TypeScript library for writing one bot that runs on Slack, Teams, Google Chat, Discord and more, with adapters and pluggable state. It is a building block rather than a hosted agent.

| | EYG cloud | Vercel Chat SDK |
| --- | --- | --- |
| What it is | A cloud that runs agents, triggers and people's programs | A library for writing chat bots |
| Platforms | The channel interface: example chat, Slack, guides for more | Many adapters maintained by Vercel and the community |
| Agents | Built in overlay agents that act through EYG | Bring your own, often with the AI SDK |
| Permissions | Channel shells | Your application code |

## Human agency

A library leaves agency with the developer. EYG cloud extends it to everyone who can read the configuration: the rules are EYG in the workspace, not logic spread through an application.

## Choose Vercel Chat SDK when

- You are writing your own bot in TypeScript and want platform adapters.

## Choose EYG cloud when

- You want the bot, its permissions and its automations already built, and configurable without redeploying code.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
