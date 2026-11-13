---
name: EYG cloud compared with Temporal
description: How EYG cloud and Temporal differ, and which to choose.
---

# EYG cloud and Temporal

Temporal is an open source durable execution platform. Workflows written as ordinary code in Go, Java, TypeScript, Python, .NET and other languages survive crashes and restarts and can run for days, self hosted or on Temporal Cloud.

| | EYG cloud | Temporal |
| --- | --- | --- |
| Source | Open source | Open source |
| Focus | What programs and agents may do | That workflows run to completion |
| Code | EYG | Many mainstream languages, with deterministic workflow code |
| Starts work | Chats, connections, webhooks, crons | Your services, schedules and signals |
| Permissions | Effect policies | Namespaces and access to the Temporal service |

## Human agency

Temporal makes long running code reliable, it does not limit what that code does. EYG cloud is about the limits: every effect passes a gate. Every EYG effect is handled by the host, which is what durable execution needs to record and replay a program, but the cloud does not resume runs after a restart yet.

## Choose Temporal when

- You run business processes across services that must complete despite failures, such as payments and provisioning.

## Choose EYG cloud when

- Work starts with people and events in chat, and agents must act within rules people own.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
