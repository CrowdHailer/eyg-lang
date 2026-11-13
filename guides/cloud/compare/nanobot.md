---
name: EYG cloud compared with nanobot
description: How EYG cloud and nanobot differ, and which to choose.
---

# EYG cloud and nanobot

nanobot is a small, readable, open source agent with a web UI and chat channels, MCP tools, memory, scheduled automations and a Python SDK. It shares EYG cloud's aim of a small core people can understand.

| | EYG cloud | nanobot |
| --- | --- | --- |
| Interface | Chat channels and a web shell | Web UI, terminal and chat channels |
| Configuration | EYG programs | Configuration files and the web UI |
| Limiting agents | Per channel shell policies over every effect | Workspace permissions, tool settings |
| Tools | Effects: files, fetch, artifacts, triggers, schedules, delegation, the configuration API | Shell, web search and fetch, MCP, files, image generation |
| Automation | Triggers on connection events, crons and timeouts | Scheduled automations and long running goals |

## Human agency

Both projects keep the core small so it can be read. EYG cloud also makes the rules small: the policy for a channel is one EYG record, and the configuration API means a person, a script and an agent use the same effects, so nothing an agent can configure is hidden from you.

## Choose nanobot when

- You want a personal assistant with a polished web UI, document tools and MCP servers today.
- You work in Python and want to embed the agent.

## Choose EYG cloud when

- Several people and channels share one deployment and need different permissions.
- You want triggers on GitHub, Bluesky or feeds, with patterns you can test.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
