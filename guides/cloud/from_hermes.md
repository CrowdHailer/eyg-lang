---
name: Migrating from Hermes Agent
description: Move a Hermes Agent gateway's profiles, platforms, toolsets, memory, skills and cron jobs to EYG cloud.
---

# Migrating from Hermes Agent to EYG cloud

Hermes runs agents on a messaging gateway with profiles, platform toolsets and terminal backends.
EYG cloud runs agents in chat platforms too, but agents only act by running EYG programs,
and everything they may do is a policy written in EYG in the workspace's `workspace.eyg`.

Read the [cloud README](../../packages/cloud/README.md) and run the [example workspace](../../examples/cloud/README.md) first.

## Concepts

| Hermes | EYG cloud |
| --- | --- |
| Profile (`~/.hermes/profiles/<name>`) | A workspace, its `workspace.eyg`, starting files and secrets |
| Multiplexed profiles, `profile_routes` | One central executor serves all workspaces. Within a workspace the `channel` function gives channels their own `llm`, `readme` and policy |
| Platform adapters and their tokens | [Channel plugins](./channel_plugins.md), configured by environment variables |
| `SessionSource` and `build_session_key` | An explicit session ID, namespaced by workspace, installation and channel, independent of the reply destination |
| `group_sessions_per_user` (default true) | One shared session per channel, every member talks to the same agent. Threads have their own session, as in Hermes |
| `require_mention`, free response channels | Every message reaches the agent. The channel `readme` tells the agent when to speak, and it posts only by choice |
| Final response sent to the chat | Ordinary replies are sent directly; explicit `Post` effects are checked by channel policy |
| `platform_toolsets`, `disabled_toolsets` | The channel's `channel_shell` policy, per channel rather than per platform |
| Terminal backends, Docker sandbox | No shell. Programs are EYG and only have the effects their channel shell allows |
| `HERMES_WRITE_SAFE_ROOT` | `shell.writes_under(roots, shell)` |
| `.env`, env passthrough, `docker_forward_env` | The workspace secrets store, read only by the configuration, and network secrets for programs |
| `MEMORY.md`, `USER.md` frozen at session start | The workspace and channel `readme`, re-evaluated every turn, and files in the session's private persistent file system |
| Skills | `/skills/<name>/SKILL.md` in the workspace's starting files |
| Cron jobs and home channels | `crons` in `workspace.eyg` name the channel to send to, and the `Cron` and `Timeout` effects |
| `delegate_task` | The `Delegate` effect, the subagent has the same channel shell |
| Busy modes `queue`, `steer`, `interrupt` | Collect: messages during a turn are given to the next turn together |
| `/new`, `/reset` | `/new` |

## Steps

### 1. One workspace per profile

For each profile create a directory with `workspace.eyg` and `files`.
Profiles that only differ in persona or model can be channels of one workspace with their own `llm` and `readme`.

### 2. Port the model and routing

A profile's `config.yaml` model and a `profile_routes` entry such as

```yaml
gateway:
  profile_routes:
    - { platform: slack, chat_id: "C0123", profile: support }
```

become the workspace `llm` and its `channel` function.

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
          readme: "You are the support agent."
        }
      }
      False(_) -> { {handle: cloud.handlers.for_channel(info), channel_shell: shell.read_only} }
    }
  }
}
```

### 3. Port toolsets to channel shells

| Hermes | Channel shell |
| --- | --- |
| Toolset without `terminal` | EYG programs never run shell commands |
| `file` tools with `HERMES_WRITE_SAFE_ROOT` | `shell.writes_under(["/projects/site"], shell.everything)` |
| Disabled `web` toolset | `shell.offline` |
| Website access policy | `{fetch: shell.fetch_hosts(["docs.example.com"]), ..shell.everything}` |
| Dangerous command approval | A gate that refuses, there are no interactive approvals |

### 4. Move secrets

Copy each value from the profile's `.env` into the workspace's store.

```sh
gleam run -m cloud/secrets -- set path/to/workspace.eyg OLLAMA_API_KEY < key.txt
```

Values that programs used through env passthrough become network secrets, so programs never see them:
`cloud.secrets.load(name, hosts)` in the configuration, with `secrets.env` and `secrets.fetch` in the channel shell.

### 5. Move memory and skills

Put the content of `SOUL.md`, `MEMORY.md` and `USER.md` that every agent needs in the workspace `readme`.
Copy facts agents should update into files, for example `files/memory/MEMORY.md`, and say so in the readme.
Unlike Hermes' frozen snapshot, an agent is told when another channel changes a file it has read.
Copy skills to `files/skills/<name>/SKILL.md`, the frontmatter is the same.

### 6. Move cron jobs

Cron jobs delivered to a home channel become `crons` naming that channel.

```eyg
crons: [{name: "digest", schedule: "0 8 * * *", channel: "general", message: "Post today's digest."}]
```

A cron message reaches the channel's agent like any other message, and the agent decides whether to post.

### 7. Connect the platforms and check

Start the cloud with the platform variables and post an `eyg` code block in each channel to check its shell.

## Not yet supported

- Allowlists and DM pairing, who can reach an agent is decided by the platform channel's membership.
- Per user sessions in groups.
- Webhook routes, they could be written as a channel plugin that reports events.
- Session search, `send_message` to other platforms and interactive approvals.
- Platforms other than the example chat, Slack, Discord and WhatsApp, see the [channel plugin guide](./channel_plugins.md).
