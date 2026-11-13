---
name: EYG cloud compared with NanoClaw
description: How EYG cloud and NanoClaw differ, and which to choose.
---

# EYG cloud and NanoClaw

NanoClaw is a small open source alternative to OpenClaw. It runs each agent in its own Linux container, so isolation comes from the operating system rather than permission checks.

| | EYG cloud | NanoClaw |
| --- | --- | --- |
| Isolation | Language level: programs only have the effects their policy gives | Operating system level: a container per agent |
| Configuration | EYG programs | A small codebase meant to be changed with an AI coding assistant |
| Limiting agents | Gates over each effect's input: paths, hosts, channels | Container mounts and the tools inside the container |
| Agents | Overlay agents that run EYG | Claude agents with a full toolset in their container |
| Automation | Triggers on events from chats and services | Scheduled tasks |

## Human agency

NanoClaw is right that complex software with full access is hard to trust. EYG cloud's answer is a language whose programs can only do what their effects allow: an agent cannot reach anything its channel shell leaves out, and you can read the shell in a few lines.

## Choose NanoClaw when

- You want agents with a full Linux environment and Claude's tools, isolated by containers.
- You are comfortable customising by editing the code.

## Choose EYG cloud when

- You want fine grained rules, for example writes only under `/channels/dev` or fetches only to one API, rather than a whole container.
- You want the rules to be data you can review and change at runtime through the configuration API.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
