# Event storming brief: EYG cloud on event sourcing

## The vision (from the product owner)

The cloud project defines a new **cloud native computer**:

- Software is not installed onto a machine. It is used by referring to its **hash** (content id),
  or "installed" by naming a hash. EYG modules and packages are already content addressed: the hub
  serves modules by CID and `@name` references resolve to the latest published version of a package
  (pinned forms exist). Publishing is signed (`packages/gleam_hub/src/eyg/hub/signatory.gleam`).
- The **file system is a shared immutable data structure**: a content addressed UnixFS/MFS tree,
  every change produces a new root CID.
- **Durable execution**: EYG programs only touch the world through effects. The result of each effect
  can be **persisted before the program resumes**, so a program appears durable even if the machine
  running it crashes mid-work: another machine replays the program, feeding it the recorded effect
  results, and continues.
- The cloud has **high audit requirements**. It will be built on **event sourcing**: every change of state
  is an immutable event; current state is a projection.

## The system as it is today (packages/cloud, Gleam on the BEAM)

Read the code under /home/user/eyg-lang/packages/cloud and the guides under /home/user/eyg-lang/guides/cloud
for details. Do not modify any files in the repository.

- `cloud.eyg` (cloud/instance) lists workspaces and named **shells** (policies) people can be given.
  `cloud/registry` runs workspaces and a users store (`users.json`). First user to sign in is admin.
- A **workspace** is configured by `workspace.eyg` (EYG, never YAML): llm, readme, files, crons,
  connections, dataclips, and a `channel` function returning each channel's config:
  `channel_shell` (policy), readme, triggers, llm.
- **Channels** come from chat plugins (example chat, Slack, Discord, WhatsApp) through `cloud/channel`
  (`Posted`, `Reacted` events; `Outbound` post/channel_name/channels).
- **Sessions**: one per conversation, an overlay agent with history (max 200 messages, in memory).
  `/new` resets. The agent runs EYG code via a `run` tool; every effect is gated by the channel shell.
- **Effects** (`cloud/beam/execute`): Post, ReadFile/WriteFile/AppendFile/DeleteFile/MakeDirectory/ReadDirectory,
  Fetch, Env, Now, Random, Flip, Sleep, StandardOut/Error, AddTrigger/StopTrigger/StartTrigger/DeleteTrigger/ListTriggers,
  Delegate (subagent), Events(connection), Cron/Timeout/CancelSchedule, Artifact/ShareArtifact,
  SQLite/SQLiteQuery (named databases), Dataclip, the configuration API (Workspaces, WorkspaceSource,
  SetWorkspaceSource, Channels, Connections, WorkspaceTriggers, Secrets, SetSecret, DeleteSecret, Users,
  Shells, SetUserShell, Traces), Bind/Unbind (web shell). Policies decide each effect: pass, mock, or unavailable.
- **Shell / policy**: a record of gates, one per effect, pure EYG functions. `shell.everything`, `read_only`,
  `writes_under`, `with_databases`, `admin`, `bind_to`, `dataclips`, `pure`...
- **Triggers**: `{name, pattern, script}` per channel; pattern is a pure function event -> bool (captured IR),
  script runs with the channel shell. Configured triggers + runtime `AddTrigger` (in memory only today).
- **Connections**: chats (ExampleChat, Slack, Discord, WhatsApp) and event sources (GitHub polling/webhooks,
  Bluesky, RSS, Hacker News, Lobsters, generic Webhook, Sentry). Each connection keeps an in-memory log of
  the latest 500 events (`Events` effect). First poll is backfill (logged, not live).
- **Schedules**: crons from config and Cron/Timeout effects (in memory).
- **Files**: shared content addressed MFS per workspace on an **in-memory block store**; changes broadcast
  to sessions which note files they read that changed.
- **Secrets**: per workspace JSON file in the data directory (chmod 600). Only configuration reads them.
  Network secrets: programs see a hash placeholder, real value injected for allowed hosts.
- **Artifacts**: versioned HTML bundles owned by a channel, shareable (in memory).
- **Databases & dataclips**: named SQLite files in the data dir; dataclips are named functions with own shell.
- **Users & web shell**: users.json, session cookie, howdy web shell that can Bind to a channel.
- **Tracing**: spans per program run and per effect with the policy decision, kept in memory (latest 2000),
  optional OTLP export.
- **Process boundary rule**: EYG closures never cross processes; each process evaluates config itself.

In short: almost all state is in memory and lost on restart; audit is only traces.

## Event storming notation

- Domain event (orange): something that happened, past tense, e.g. `EffectResultRecorded`.
- Command (blue): an intention that may be rejected, e.g. `RecordEffectResult`.
- Actor (small yellow): who issues the command (person, agent, trigger, scheduler, connection, admin).
- Aggregate (big yellow): the consistency boundary that accepts commands and emits events.
- Policy (lilac): "whenever X then Y" reactions, e.g. "whenever TriggerMatched, run the script".
- Read model / view (green): projections people or programs read.
- External system (pink): Slack, GitHub, the hub, model providers...
- Hot spot (red): a question, conflict or risk to resolve.
- Bounded context: a group of the above with its own language.
