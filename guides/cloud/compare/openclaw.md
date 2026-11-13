---
name: EYG cloud compared with OpenClaw
description: How EYG cloud and OpenClaw differ, and which to choose.
---

# EYG cloud and OpenClaw

OpenClaw is an open source gateway that runs personal and team agents in chat platforms, configured with `openclaw.json` and workspace files such as `AGENTS.md`. EYG cloud follows OpenClaw's model, agents live in channels and speak by choosing to send a message, and replaces its configuration and tool policies with EYG programs.

| | EYG cloud | OpenClaw |
| --- | --- | --- |
| Where agents live | Chat channels, one session per conversation | Chat channels and DMs, sessions per peer, channel or group |
| Configuration | `workspace.eyg` and `cloud.eyg`, evaluated programs | `openclaw.json` (JSON5) and markdown workspace files |
| Limiting agents | A channel shell: one gate function per effect, over the effect's input | Tool allow and deny lists, profiles, sandbox modes, per group tool settings |
| Replying | Only by performing `Post` | Automatic replies, or a message tool with `visibleReplies` |
| Automation | Pure trigger patterns over events from chats, GitHub, Sentry, webhooks, Bluesky, feeds and news sites, crons, timeouts | Hooks, cron jobs and heartbeats |
| Code from people | `eyg` code blocks run with the channel shell | Slash commands and tools |
| Size | One BEAM process, a few thousand lines of Gleam and EYG | A large TypeScript codebase with many plugins |

## Human agency

OpenClaw gives people control through settings: allow lists, pairing and sandbox modes chosen from options the project defines. EYG cloud gives control through programs: a policy is a function you write, so you can express rules the authors did not anticipate, test them with the EYG test runner and review them like any other code. Both are self hosted.

## Choose OpenClaw when

- You want the broadest set of chat platforms and integrations today.
- You prefer agents that run shell commands on a host or in Docker.
- Your team configures in JSON and markdown and does not want to learn a language.

## Choose EYG cloud when

- You want to read, test and version every permission as code.
- You need a policy that inspects what an effect does, a path or a host, not only which tool it is.
- You want events from services, not only messages, to run your own triggers.

The [migration guide](../from_openclaw.md) maps OpenClaw concepts to EYG cloud.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
