---
name: Comparisons
description: How EYG cloud compares with other agent gateways, frameworks and automation services.
---

# EYG cloud compared

EYG cloud runs agents in chat channels and triggers on events from chats and services,
with everything they may do written in EYG and checked by policies people own.
It is always aiming to maximise human agency: people can read, test and change every rule,
agents must choose to act, and the same API serves people, scripts and agents.

## Open source

- [OpenClaw](./openclaw.md), open source agent gateway. OpenClaw is an open source gateway that runs personal and team agents in chat platforms, configured with `openclaw.json` and workspace files such as `AGENTS.md`.
- [Hermes Agent](./hermes.md), open source agent gateway. Hermes Agent is an open source agent with a messaging gateway, profiles, platform toolsets and terminal backends.
- [nanobot](./nanobot.md), open source agent. nanobot is a small, readable, open source agent with a web UI and chat channels, MCP tools, memory, scheduled automations and a Python SDK.
- [NanoClaw](./nanoclaw.md), open source agent gateway. NanoClaw is a small open source alternative to OpenClaw.
- [ElizaOS](./elizaos.md), open source agent framework. ElizaOS is an open source framework and runtime for autonomous agents with characters, plugins, many platform clients and a cloud offering.
- [Vercel Chat SDK](./chat_sdk.md), open source library. Chat SDK is a TypeScript library for writing one bot that runs on Slack, Teams, Google Chat, Discord and more, with adapters and pluggable state.
- [n8n](./n8n.md), fair code workflow automation. n8n is a workflow automation tool with a visual editor, hundreds of integrations and AI agent nodes.

## Closed source

- [Zapier](./zapier.md), closed source automation. Zapier is a hosted automation service that connects thousands of apps with Zaps, and offers AI agents and chatbots.
- [Lindy](./lindy.md), closed source ai agents. Lindy is a hosted platform for building AI agents that work across email, calendars, chat and business apps.
- [Microsoft Copilot Studio](./copilot_studio.md), closed source agent builder. Copilot Studio is Microsoft's hosted builder for agents in Teams, Microsoft 365 and other channels, with connectors to Microsoft and third party services and administration through the Power Platform.
- [Claude](./claude.md), closed source assistant and agents. Claude is Anthropic's assistant, available in its apps, in Slack and as Claude Code, which runs coding agents locally or in the cloud and can be scheduled.
- [ChatGPT agents](./chatgpt.md), closed source assistant and agents. ChatGPT is OpenAI's assistant.
- [IFTTT](./ifttt.md), closed source automation. IFTTT connects services with applets: if this happens, then do that.

## What EYG cloud does not do yet

- Run shell commands. Programs only have EYG effects, an agent cannot install a package or run a binary.
- Interactive approvals. Gates decide immediately, there is no prompt to approve an action.
- Many platforms. The example chat and Slack plug into the channel interface, others need a plugin, see the [channel plugin guide](../channel_plugins.md).
- Accounts. The web shell signs people in by name, put it behind your own authentication.
