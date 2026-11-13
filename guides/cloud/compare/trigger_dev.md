---
name: EYG cloud compared with Trigger.dev
description: How EYG cloud and Trigger.dev differ, and which to choose.
---

# EYG cloud and Trigger.dev

Trigger.dev is an open source platform for background tasks in TypeScript. Tasks run for as long as they need with retries, queues, schedules and observability, in Trigger.dev's cloud or self hosted.

| | EYG cloud | Trigger.dev |
| --- | --- | --- |
| Source | Open source | Open source |
| Where code lives | Workspace configuration and channel triggers | Your TypeScript project, deployed to Trigger.dev |
| Starts work | Chat messages, connection events, webhooks, crons | Your code, schedules and webhooks |
| Long running work | Agent turns, subagents, schedules | Durable tasks with retries and waits |
| Permissions | Effect policies | The task's code and environment variables |

## Human agency

Trigger.dev gives a TypeScript application reliable background work, controlled by the application's developers. EYG cloud is for the people around the application: they write triggers in chat channels, agents act for them, and every action is checked by a policy they can read.

## Choose Trigger.dev when

- Your application is TypeScript and needs durable background jobs that you deploy with it.

## Choose EYG cloud when

- The people who decide what happens are in chat, not in the codebase.
- You want agents and automations limited by policies rather than by code review.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
