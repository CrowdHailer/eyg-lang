# EYG cloud

Cloud extends main’s central session actor with checked workspace configuration,
channel policies, triggers, schedules, a web shell and an HTTP API. The session
actor executes agent turns and programs serially. Ordinary replies are sent
directly; explicit effects pass through the configured policy.

Run `gleam run` from this directory. Without a cloud or workspace configuration,
main’s Slack/Discord startup adapters and Clockwork schedules run as usual.
`SLACK_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID`, `OLLAMA_API_KEY` and
`EYG_ORIGIN` retain their startup meanings.

With `CLOUD=path/to/cloud.eyg`, the process loads a record containing `workspaces`
(`[{name, file}]`) and `shells` (a record of named policies). Alternatively,
`WORKSPACE=path/to/workspace.eyg` loads one workspace. `PORT` defaults to 8081;
`CLOUD_ORIGIN` sets the public origin used by artifact URLs.

A workspace defines `llm`, `channel`, and optionally `readme`, `files`, `crons`
and `connections`. The channel function receives `{platform, installation, id,
name}` and returns `on_input`, `channel_shell`, and optional model, context and
triggers. `on_input` receives the platform’s native input. Source and imports are
type checked before trusted configuration is evaluated. Keywords cannot be used
as record fields; use `on_input`, as documented in the syntax guide.

`cloud.mock_all` is supplied by the runtime. Policies override its gates with
pure functions returning `Pass(input)` or `Mock(result)`. The host checks every
gate’s type. There is no separate rejection protocol or runtime value checker.

Configured adapter implementations land after deployment. Main’s basic native
adapters remain available throughout the branch.

## State

Session file roots, history, pending observations, users, secrets, edited
workspace source and artifacts live in memory. Files remain private to their
session and survive successive commands; lexical bindings do not. `/new` clears
history and observations while retaining the current session’s files. The newest
200 history messages are retained. Agents have no round limit, so a long-running
turn can hold the central queue.

There are no JSON snapshots, local SQLite stores or writable data volumes.
Configuration and seed files are read-only startup inputs. API source edits do
not overwrite them. A web user’s files remain private across channel bindings;
binding grants policy and a reply destination, not another session’s files.

The intended system holds state in memory across a cluster. This branch does not
implement replication or recovery after all state owners stop. See
[the state decision](../../notes/cloud-memory-state.md).

## HTTP and automation

`GET /` reports service status. `/login` and `/shell` expose the web shell;
`POST /api/<Operation>` performs an operation using the signed-in user’s policy.
The first user is an administrator. This example login needs front-door
authentication before public use. Operator pages and quick-trigger widgets are
not included.

`WorkspaceSource`, `SetWorkspaceSource`, `Secrets`, `SetSecret`, `DeleteSecret`
and user-policy operations update actor-held state. Secrets are readable only
from trusted configuration. Programs use private file effects, explicit posts,
delegation, trigger management and scheduling according to their policy.

The [network-secrets package](../../eyg_packages/network_secrets/README.md) can
substitute credentials only into requests to configured HTTPS hosts. It loads
from the workspace's in-memory secrets and adds no host persistence.

Clockwork parses five-field UTC schedules. Configured timers reuse main’s
next-occurrence helper; duplicate ticks do not deliver twice. Scheduled work
retains its session identity, policy context and reply destination.

Artifacts are versioned bundles held in memory and served with a sandbox content
security policy. The hub does not store artifacts. Tracing records execution
spans in memory. See [process boundaries](../../notes/cloud-process-boundaries.md)
for why evaluated EYG closures do not cross configured actor boundaries.
