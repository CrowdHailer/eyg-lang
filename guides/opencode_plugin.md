---
name: EYG as an OpenCode plugin
description: Add an EYG tool with computer effects, policy-aware subagents and prompt guidance.
---

# EYG as an OpenCode plugin

The public plugin in [opencode_plugin](../packages/opencode_plugin/) adds an
EYG tool through OpenCode's [plugin interface](https://opencode.ai/docs/plugins/).
It targets the pinned v1.19.0 SDK. Its configuration, runtime, hooks and build
tooling are Gleam; a three-line entry exposes the compiled factory.

From packages/opencode_plugin:

```sh
bun install
gleam run -m build
gleam test
gleam test --runtime node
gleam run -m extension_test
```

In your project's opencode.json, use the absolute location of the built plugin:

```json
{
  "plugin": ["file:///absolute/path/to/eyg-lang/packages/opencode_plugin/dist/eyg.mjs"],
  "permission": {"*": "deny", "eyg": "allow", "eyg_escalate": "ask"}
}
```

This permits the EYG tool and asks before escalation. Other tools use
OpenCode's own permissions. For complete native and MCP tool routing, use the
separate [dispatcher integration](./opencode_dispatcher.md) instead of loading
both paths. The plugin supplies computer effects such as ReadFile and WriteFile;
the dispatcher also supplies native Read, Edit, Bash and other host tools.

Write .opencode/eyg.eyg in your project:

```eyg
{
  policy: {
    read_file: Pass,
    write_file: (_) -> { Mock(Error("read only")) },
    task: Pass,
    escalate: Pass
  },
  context: {readme: "Read the project and explain proposed changes."},
  agents: {reader: {read_file: Pass}}
}
```

OPENCODE_EYG_CONFIG overrides this file; the next fallback is
~/.config/opencode/eyg.eyg. An explicit override must be readable. Without a
file, computer file effects are limited to project paths. Configuration is
trusted EYG, cached by exact content. Changed contents reset session policy
assignments; invalid configuration fails execution. The [policy guide](./harness_policies.md)
explains gate composition, import checks and filesystem limits.

The agent receives the allowed effect signatures, context readme, syntax and
builtin guides in its system prompt. Every call starts a fresh scope with
context available. Captured StandardOut and StandardError accompany the final
value. Relative paths resolve from the project; gates see absolute paths.

```eyg
perform Task({agent: "reader", prompt: "Inspect README.md", policy: {read_file: Pass}})
```

Task creates an SDK child session, stores its restricted policy before sending
the prompt and returns the last text answer. A configured named-agent policy
is its trusted starting point; otherwise it restricts the parent's policy.
Later hooks and tool calls retain the assigned restriction. Escalate has the
same shape, replacing that policy only after ctx.ask approves eyg_escalate.
A refusal creates no child session.

The package tests exercise the pinned SDK, native callbacks, denied operations, inherited child policies and tool routing without calling a model service.
