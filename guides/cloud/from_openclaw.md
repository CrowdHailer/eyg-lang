---
name: Migrating from OpenClaw
description: Move an OpenClaw gateway's agents, channels, policies, skills and cron jobs to EYG cloud.
---

# Migrating from OpenClaw to EYG cloud

EYG cloud follows OpenClaw's approach: agents live in chat platforms, every conversation has a session,
and an agent speaks by choosing to send a message, like OpenClaw's `visibleReplies: "message_tool"`.
The difference is that everything OpenClaw configures in `openclaw.json`, and enforces with tool policies and sandboxes,
is a program in EYG cloud. A workspace is configured by `workspace.eyg`, and what each channel may do is a policy written in EYG.

Read the [cloud README](../../packages/cloud/README.md) and run the [example workspace](../../examples/cloud/README.md) first.

## Concepts

| OpenClaw | EYG cloud |
| --- | --- |
| Gateway | A cloud process running one workspace |
| Agent, its workspace and `agentDir` | A workspace. A channel can set its own `llm` and `readme` to act as a different agent. Agents that must not share files or secrets are separate workspaces |
| Channel plugin and account (`channels.slack`) | A [channel plugin](./channel_plugins.md), configured in `connections` in `workspace.eyg` |
| `bindings` | The workspace's `channel` function, which matches on `{platform, id, name}` |
| Session key, `dmScope`, `groupScope` | One session per conversation: each channel, DM and thread has its own. DMs are not merged into a main session |
| `visibleReplies: "message_tool"`, `message(action=send)` | Ordinary replies are sent directly; additional messages use the policy-checked `Post` effect |
| `NO_REPLY` | Not posting |
| Mention gating, `requireMention`, ambient room events | Every message reaches the agent, as OpenClaw's room events. The channel `readme` tells the agent when to speak |
| `tools.allow`/`deny`, `tools.profile`, sandbox, `groups.*.tools` | The channel's `channel_shell` policy. Gates are functions over effect inputs, so they can check paths and hosts, not just tool names |
| Workspace files `AGENTS.md`, `SOUL.md`, `USER.md` | The workspace `readme` and channel `readme` in `workspace.eyg`, re-evaluated every turn |
| `MEMORY.md` and memory files | Files in the session's private persistent file system, agents read and write them with file effects |
| Skills | `/skills/<name>/SKILL.md` in the workspace's starting files |
| Auth profiles and secrets | The workspace secrets store, read only by the configuration |
| Cron jobs and heartbeats | `crons` in `workspace.eyg`, and the `Cron` and `Timeout` effects |
| Hooks | Triggers, `{name, pattern, script}` per channel |
| `sessions_spawn`, subagents | The `Delegate` effect, subagents run with the same channel shell |
| Canvas | Artifacts, versioned HTML pages owned by a channel |
| Queue `steer`, `followup`, `collect` | Collect: messages that arrive during a turn are given to the next turn together |
| `/new`, `/reset` | `/new` |

## Steps

### 1. One workspace per gateway

Create a directory with a `workspace.eyg` and a `files` directory.
If your gateway runs several agents that share a trust boundary, keep one workspace and give channels their own `llm` and `readme`.
If agents must be isolated, as OpenClaw recommends separate gateways for untrusted users, run one cloud process per workspace.

### 2. Port the model and bindings

An OpenClaw configuration such as

```json5
{
  agents: { entries: { support: { model: "anthropic/claude", workspace: "~/.openclaw/workspace-support" } } },
  bindings: [{ match: { channel: "slack", peer: { kind: "channel", id: "C0123" } }, agentId: "support" }],
}
```

becomes a workspace whose `channel` function chooses each channel's configuration.

```eyg
let cloud = import "../../eyg_packages/cloud/index.eyg"
let shell = cloud.shell

let api_key = match perform Secret("OLLAMA_API_KEY") {
  Ok(key) -> { Some(key) }
  Error(_) -> { None({}) }
}

{
  llm: {provider: Ollama({origin: "https://ollama.com", api_key}), model: "glm-5.3"},
  readme: "You are the team's assistant.",
  files: "./files",
  channel: (info) -> {
    let {id, name} = info
    match !equal(id, "C0123") {
      True(_) -> {
        {
          handle: cloud.handlers.for_channel(info), channel_shell: shell.writes_under(["/channels/support"], shell.everything),
          readme: "You are the support agent, answer customer questions."
        }
      }
      False(_) -> { {handle: cloud.handlers.for_channel(info), channel_shell: shell.read_only} }
    }
  }
}
```

### 3. Port tool policies to channel shells

OpenClaw combines tool allow and deny lists, sandbox modes and per group tool restrictions.
A channel shell is a complete record of typed gates, checked whenever it is set.
Start with `cloud.reject_all` and override the gates that the channel needs.

| OpenClaw | Channel shell |
| --- | --- |
| `deny: ["group:runtime"]` | EYG has no shell execution, programs only have the effects in the shell |
| `deny: ["group:fs"]` or `workspaceAccess: "ro"` | `shell.read_only` |
| `docker.binds: ["/data:/data:ro"]` | `shell.writes_under(["/data"], shell.everything)` |
| `deny: ["web_fetch"]` | `shell.offline` |
| A fetch allowlist | `{fetch: shell.fetch_hosts(["api.github.com"]), ..shell.everything}` |
| `deny: ["message"]` | `{post: (_) -> { Reject({}) }, ..shell.everything}` |

Per sender restrictions, `toolsBySender`, have no equivalent yet: a shell applies to everyone in the channel.

### 4. Move secrets

Save each secret in the workspace's store, it is kept in the workspace's `.data` directory.

```sh
gleam run -m cloud/secrets -- set path/to/workspace.eyg GITHUB_TOKEN < token.txt
```

Credentials that programs need for an API become network secrets: programs see a placeholder and the policy adds the real value to requests to the API's host.

```eyg
let github = match cloud.secrets.load("GITHUB_TOKEN", ["api.github.com"]) {
  Ok(token) -> { [token] }
  Error(_) -> { [] }
}
let shell_with_github = {
  env: cloud.secrets.env(github),
  fetch: cloud.secrets.fetch(github, shell.pass),
  ..shell.everything
}
```

### 5. Move workspace files, memory and skills

Put the instructions from `AGENTS.md` and `SOUL.md` in the workspace `readme`, and channel specific ones in channel readmes.
Copy skills to `files/skills/<name>/SKILL.md`, the frontmatter format is the same.
Copy `MEMORY.md` and memory files into `files`, for example `files/memory/`, and tell agents in the readme to read and update them.
OpenClaw keeps `MEMORY.md` out of group sessions, in EYG cloud use `writes_under` and the readme to decide which channels use which memory files.
Each session keeps a private filesystem. Changes stay within that session; explicit sharing between sessions is future work.

### 6. Move cron jobs and hooks

OpenClaw cron jobs become `crons`, sent to a channel's session.

```eyg
crons: [{name: "standup", schedule: "0 9 * * 1-5", channel: "general", message: "Post the standup reminder."}]
```

Hooks that respond to messages or reactions become triggers.

```eyg
triggers: [{
  name: "summarise",
  pattern: cloud.triggers.reaction("books"),
  script: match {
    ChatReacted(reacted) -> { perform Delegate(reacted.message.text) }
    SlackReaction(reacted) -> { perform Delegate(reacted.message.text) }
    DiscordReaction(reacted) -> { perform Delegate(reacted.message.content) }
    | (_) -> { Error("not a reaction") }
  }
}]
```

### 7. Connect the platforms and check

Start the cloud with the platform variables, post in each channel and check what agents can do by posting `eyg` code blocks,
which run with that channel's shell.

## Not yet supported

- DM pairing and sender allowlists. Who can reach an agent is decided by who can post in the platform channel.
- A main session shared by every DM.
- Interactive approvals, `/approve`. Gates decide immediately.
- Sending to other conversations, `Post` only posts to the program's own conversation or thread.
- Edits and deletions are not reported to agents.
- Steering or interrupting a running turn.
- Session search across conversations.
