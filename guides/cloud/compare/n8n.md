---
name: EYG cloud compared with n8n
description: How EYG cloud and n8n differ, and which to choose.
---

# EYG cloud and n8n

n8n is a workflow automation tool with a visual editor, hundreds of integrations and AI agent nodes. It can be self hosted under its sustainable use licence.

| | EYG cloud | n8n |
| --- | --- | --- |
| Building automations | EYG code: pure patterns and scripts | A visual node editor, with code nodes |
| Triggers | Events from chats, GitHub, Bluesky, RSS, Hacker News and Lobsters | Hundreds of trigger nodes and webhooks |
| Agents | Agents in every channel, with policies | AI agent nodes inside workflows |
| Permissions | Per channel shell policies, also for people in the web shell | Credentials per workflow and user roles |
| Configuration as code | Always, EYG files | Workflows export as JSON |

## Human agency

A visual editor makes automation approachable, but the rules live in many node settings. EYG cloud keeps every rule in a program: the trigger, what it may do and who may change it are all text you can read top to bottom.

## Choose n8n when

- You need many integrations now and prefer building in a visual editor.
- Your automations are mostly data pipelines between business systems.

## Choose EYG cloud when

- You want automations and agents to share one permission model.
- You want automations that are short programs you can diff and test, not diagrams.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
