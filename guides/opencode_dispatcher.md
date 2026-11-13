---
name: EYG as the OpenCode tool dispatcher
description: Route native and MCP tools through EYG while retaining host permissions and child policies.
---

# EYG as the OpenCode tool dispatcher

[opencode_plugin](../packages/opencode_plugin/) can wrap the complete tool set
of the pinned OpenCode v1.19.0 dispatcher. Runtime logic, policy handling,
configuration, argument mapping and tooling are Gleam. Small native bindings
connect the AI SDK and its existing execution callbacks.

From packages/opencode_plugin:

```sh
bun install
gleam run -m build
gleam test
gleam test --runtime node
gleam run -m upstream_check
```

The last command downloads the pinned [upstream tools.ts](https://github.com/anomalyco/opencode/blob/v1.19.0/packages/opencode/src/session/tools.ts) once, verifies its
SHA-256, applies the integration and runs the actual upstream resolve function
with deterministic services and the official AI SDK/Effect versions. It checks
native and MCP tools, permissions, before/after hooks, original program metadata,
child-policy retention, both dispatcher return paths and cancellation completion.
It makes no model call and starts no OpenCode UI.

To integrate an existing v1.19.0 source checkout, run from this package:

```sh
gleam run -m install -- /absolute/path/to/opencode
```

The installer checks the original dispatcher bytes before writing, copies the
Gleam bundle with embedded resources, and adds bindings at the dispatcher return points
and Task metadata boundary. Running it again is safe. Other or locally changed
dispatchers are refused. Build and run that checkout using OpenCode's own
development instructions. The published plugin hooks alone do not expose this
complete dispatcher; use this integration separately from the EYG plugin.

OPENCODE_EYG selects the mode: only, the default, exposes EYG alone; gate keeps
direct tool declarations and routes each call through the same effect policy;
off returns the native tool set. Native tools still run their ordinary host
validation, permissions, hooks and abort path. MCP tools follow that path too.

Configuration is OPENCODE_EYG_CONFIG, then .opencode/eyg.eyg in the project,
then ~/.config/opencode/eyg.eyg. An explicit override must be readable.
Configuration is cached by exact contents; changing it creates a fresh policy
router. Without a file, computer file effects stay within the project and native
tool gates allow their own OpenCode permission rules to decide access.
Shell and web tools have no default gate.

Programs use snake case fields, for example `perform Read({file_path: "README.md"})`.
The host maps these back to each tool's original schema. A direct call in gate
mode is run as the same perform expression, including Mock and denial results.
The [policy guide](./harness_policies.md) explains gate composition and defaults.

Task accepts an optional policy record alongside its native parameters:

```eyg
perform Task({
  subagent_type: "explore",
  description: "Inspect source",
  prompt: "Read the project and report what you find.",
  policy: {read: Pass, grep: Pass, glob: Pass}
})
```

The policy field is removed before native validation. Task's session notification
stores the restricted policy before its child runs. Later calls in that session
keep it. A configured policy for the named agent is its trusted starting point;
otherwise the parent policy is restricted. Policies are held for the process
lifetime, and recreating the router after a configuration change resets them.

The package tests exercise the pinned SDK, native callbacks, denied operations, inherited child policies and tool routing without calling a model service.
