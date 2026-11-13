---
name: EYG cloud compared with Hermes Agent
description: How EYG cloud and Hermes Agent differ, and which to choose.
---

# EYG cloud and Hermes Agent

Hermes Agent is an open source agent with a messaging gateway, profiles, platform toolsets and terminal backends. Like EYG cloud it can serve many chat platforms from one process. EYG cloud agents act only by running EYG programs, and what each channel may do is a policy in `workspace.eyg`.

| | EYG cloud | Hermes Agent |
| --- | --- | --- |
| Where agents live | Chat channels and threads | Messaging platforms, sessions per chat or per user |
| Configuration | EYG programs | `config.yaml` profiles, `.env` files |
| Limiting agents | Channel shells, gates over effect inputs | Toolsets per platform, write safe roots, approvals for dangerous commands |
| Execution | EYG programs with the channel's effects, no shell | Terminal backends: local, Docker, SSH and others |
| Memory | Private persistent session files and history; fresh execution scope | `MEMORY.md` and `USER.md` snapshots |
| Automation | Pure triggers over connection events, crons, timeouts | Cron jobs delivered to home channels |

## Human agency

Hermes asks for approval before dangerous terminal commands, people stay in the loop by answering prompts. EYG cloud moves the decision earlier: a gate decides every effect, before anything runs, so there are no prompts to rubber stamp, and the rule is visible to everyone in the channel's configuration.

## Choose Hermes Agent when

- You want an agent that can drive a real terminal and existing command line tools.
- You already use its profiles and skills ecosystem.

## Choose EYG cloud when

- You want configuration that is checked by evaluating it, not YAML.
- You want one policy that covers agents, subagents, triggers and people in the same channel.

The [migration guide](../from_hermes.md) maps Hermes concepts to EYG cloud.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
