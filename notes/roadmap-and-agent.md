---
name: Roadmap on the agent branch
description: How the roadmap commits sit on the agent branch, what was merged or dropped as duplicate, what is independent and what is easier now.
date: 2026-11-12
---

The roadmap's 61 commits sit on top of the agent commits in one branch, so the cloud comes first.
The agent commits add EYG cloud: agents in chat channels (the example chat, Slack, Discord and WhatsApp),
channel shells, triggers on connection events, the configuration API, the web shell and tracing.
The two overlapped in very few files, `entry.eyg`, the CI workflow and `packages/otel`, and those were merged.

## Merged or dropped as duplicate

| Roadmap | Agent branch | Result |
| --- | --- | --- |
| `packages/otel`, OTLP export for Loam on JavaScript | `packages/otel` with the roadmap's span and trace modules, used by the cloud on the BEAM | One package. Span and trace were identical. The clock reads the high resolution clock on JavaScript, as the roadmap's did, and `os:system_time` on Erlang, so the cloud uses the same modules and the exporter stays JavaScript |
| Artifact bundle rules | Cloud and browser-local artifact hosts | Both use the independent `artifact_bundle` package; the hub stores no artifacts |
| Overlay system prompts gain a `policed` flag, the interpreter gains query `Table` values | The cloud calls overlay and renders values | Adapted in the roadmap commits that made each change |
| CI package lists | `cloud` in the Erlang matrix | Both kept |

Span names already agree: Loam records `eyg.run → eyg.eval → eyg.effect.<name>`, the cloud `eyg.run → eyg.effect.<Name>`,
under its own spans for agent turns, triggers and web shell runs. Both use the standard `OTEL_*` variables.

## Independent

These do not interact with the cloud and would land the same without it.

- The native Zig interpreter, oracle tested TUI, Git runtime and the talk's measurements.
- Typed query literals, datalog planning, SQLite resolution, the movies example and editor highlighting.
- Soundness search of the type checker and the record label check.
- The Raspberry Pi image, embedded hosts (TodoMVC, Hashi, nginx) and building CLI executables in Gleam.
- Package resolution, release metadata caching and preserving standard input in the CLI.
- Bounded interpreter runs, compiled execution, scoped masks and shallow handlers.

## Easier now the agent branch exists

- **Recorded agents and trajectories.** Cloud sessions are overlay agents. Recording their turns as portable trajectories,
  with secret redaction, gives a history of what an agent did in a channel that people can replay and review.
  Trajectories could be kept in the workspace's file system where other channels' agents can read them.
- **Effect recording and tracing.** The cloud already traces every effect with the policy's decision. Loam's recorded
  effects and profiles use the same span model, so CLI and cloud traces can be read side by side in one collector.
- **Executable authorization policies and agent oversight.** Channel shells are executable policies over effects.
  The roadmap's authorization tutorial and oversight comparisons can use the cloud's shells, `bind_to` and the configuration
  API as worked examples, and policies written for one apply to the other.
- **Channel based authorization.** The Slack prototype checks GitHub submitters against Slack channel membership.
  The cloud has a Slack plugin, a GitHub connection and channel shells, so the check can be a trigger pattern and
  a gate in a workspace rather than a separate service.
- **Native tool policies for Pi and OpenCode.** The same policy records gate the cloud's effects, so a policy library
  shared between Pi, OpenCode and cloud channels removes three copies of the same rules.
- **Retained typed shell and terminal components.** The web shell is a Lustre server component served by howdy.
  The retained shell and the TUI can be rendered the same way, as the howdy branch started, giving the web shell
  the structural editor and typed cells.
- **Artifact workspaces.** Cloud artifacts are owned and hosted by channels; `ShareArtifact` permits other channels in the workspace to revise them.
  Browser artifacts retain local revisions, previews and portable exports. The hub does not publish or store artifacts.
- **Sealed sandboxes and offline evaluation.** Cloud channels are policy sandboxes for EYG programs. Evaluating agent
  sessions offline against recorded channel events, from the connection logs, tests a workspace's triggers and shells
  without touching live services.

## Building the roadmap commits

Each roadmap commit keeps its original content and checks, and also builds the cloud package, which the roadmap did not have.
Where a roadmap commit changed an API the cloud uses, or the requirements of a local package the cloud depends on,
the cloud's adaptation and refreshed `manifest.toml` are part of that commit.
The tip builds and tests everything both branches test.
