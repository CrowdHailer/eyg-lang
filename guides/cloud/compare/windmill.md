---
name: EYG cloud compared with Windmill
description: How EYG cloud and Windmill differ, and which to choose.
---

# EYG cloud and Windmill

Windmill is an open source developer platform that turns scripts in Python, TypeScript, Go, Bash, SQL and other languages into webhooks, scheduled jobs, workflows and internal apps, self hosted or in Windmill's cloud.

| | EYG cloud | Windmill |
| --- | --- | --- |
| Source | Open source | Open source, with enterprise features |
| Code | EYG | Many mainstream languages |
| Triggers | Chats, connections, webhooks, crons | Webhooks, schedules and other trigger sources |
| Permissions | Effect policies per channel | Workspace roles, groups and permissions on scripts and resources |
| Interfaces | Chat channels, the web shell, artifacts | Generated forms and an app builder |

## Human agency

Windmill makes scripts easy to run and share, and controls who can run them and which resources they get. Inside a script, code can do whatever its language and runtime allow. In EYG cloud every effect a program performs passes a gate people wrote, so the limits hold inside the program too, including for code an agent writes.

## Choose Windmill when

- Your team writes scripts in Python or TypeScript and wants to schedule them, chain them and give them a UI.
- You need workers for heavy jobs.

## Choose EYG cloud when

- Agents write and run code and you want what they may do to be enforced, not trusted.
- Work starts in chats and you want people, agents and triggers on one policy model.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
