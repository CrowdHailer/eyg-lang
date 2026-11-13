---
name: Configuration API
description: Read and change a cloud's workspaces, connections, channels, secrets and people, from a shell, a channel or HTTP.
---

# The configuration API

Everything about a cloud can be read and changed with effects.
The same effects are used by the [web shell](./web_shell.md), by agents in a channel whose shell allows them,
and by the HTTP API, so there is one API and every caller is gated by an EYG policy.

| Effect | Policy field | Input | Returns |
| --- | --- | --- | --- |
| `Workspaces` | `workspaces` | `{}` | `[{name, file}]` |
| `WorkspaceSource` | `workspace_source` | workspace | the source of its `workspace.eyg` |
| `SetWorkspaceSource` | `set_workspace_source` | `{workspace, source}` | saved only if the new source evaluates |
| `Channels` | `channels` | workspace | `[{platform, id, name}]` of every connected chat |
| `Connections` | `connections` | workspace | `[{name, kind, channel}]` |
| `WorkspaceTriggers` | `workspace_triggers` | `{workspace, channel}` | `[{name, active}]` |
| `Secrets` | `secrets` | workspace | the names of its secrets, never values |
| `SetSecret` | `set_secret` | `{workspace, name, value}` | |
| `DeleteSecret` | `delete_secret` | `{workspace, name}` | |
| `Users` | `users` | `{}` | `[{name, admin, shell}]` |
| `Shells` | `shells` | `{}` | the names of the shells in `cloud.eyg` |
| `SetUserShell` | `set_user_shell` | `{user, shell}` | |

Every effect returns `Ok(value)` or `Error(reason)`.
Changes to a channel's configuration apply to the next message, connections and crons apply when the cloud restarts.

## Policies

The [cloud EYG package](../../eyg_packages/cloud/shell.eyg) has presets:

- `shell.observe` reads everything except secret values.
- `shell.configure` reads and changes everything.
- `shell.admin` is every channel effect and `configure`, for a trusted channel.

A gate can narrow an operation, for example a channel that may only change one workspace:

```eyg
{
  set_workspace_source: (change) -> {
    match !equal(change.workspace, "marketing") {
      True(_) -> { Pass(change) }
      False(_) -> { Mock(Error("only the marketing workspace")) }
    }
  },
  ..shell.configure
}
```

## From a channel

A channel whose `channel_shell` has these gates lets its agent run the cloud.
The example workspace's `#founders` channel uses `shell.admin`, so you can ask its agent
"which connections post to #news?" and it performs `Connections("example")`.
Treat such a channel like an admin account: only trusted people should be able to post in it.

## Over HTTP

`POST /api/<Effect>` with the input as JSON performs the effect for the signed in person,
the session cookie identifies them. The server runs `perform <Effect>(input)` with that person's shell policy,
exactly as if they typed it into the web shell.

```sh
curl -b cookies -X POST http://localhost:8081/api/Connections -d '"example"'
```

JSON objects are records, arrays are lists and booleans are `True({})` and `False({})`.
Results are EYG values as JSON: `{"Ok": [...]}`, tags as objects with one key.
An effect the policy does not allow is answered with `403` and `{"error": "Effect Secrets is not allowed by policy"}`.

The admin page at `/admin` is built only on these requests.
