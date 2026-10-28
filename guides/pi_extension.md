---
name: EYG in Pi
description: Expose Pi tools as effects with inherited policies and usage reporting.
---

# EYG in Pi

[packages/pi_extension](../packages/pi_extension/) adds one EYG tool to Pi 1.2.0.
Its runtime and tools are Gleam; five bindings access pi-agent-core and TypeBox.
It uses pinned official SDK packages. The
[Pi extension API](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md)
provides registration, callable tools and loadout declarations.

Pi requires Node 22.19 or newer; this check used Node 24.15. Bun builds the
extension. From packages/pi_extension:

The optional bash adapter's integration check also requires the EYG CLI on PATH.

```sh
bun install
gleam run -m build
gleam test
gleam test --runtime node
```

Start Pi from your project with
`pi -e /absolute/path/to/packages/pi_extension/dist/index.mjs --eyg-only`.
The installed local CLI is also available through
`node /absolute/path/to/packages/pi_extension/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js`.
Pass the same extension and flag. Configure a model through Pi as usual.

Write .pi/eyg.eyg in that project:

```eyg
{
  policy: {
    read: Pass,
    edit: Pass,
    write: (request) -> {
      match !string_ends_with(request.path, "notes.md") {
        True(_) -> { Pass(request) }
        False(_) -> { Mock(Error("only notes.md can be written")) }
      }
    },
    task: Pass,
    escalate: Pass
  },
  context: {readme: "Inspect files and keep changes in notes.md."}
}
```

PI_EYG_CONFIG overrides the project file; the next fallback is eyg.eyg in
PI_CODING_AGENT_DIR, or ~/.pi/agent. Without a file, the bundled default permits
computer file effects within the project. Its read_file gate controls ReadFile;
native Pi Read uses read. Changed configuration is reloaded; invalid source
fails execution instead of falling back to the previous policy.

The model can run `perform Read({path: "fruit.txt"})` and
`perform Write({path: "notes.md", content: "two fruit"})`. The host normalizes
file paths before gates. Pi's validation, hooks and events still run when EYG
calls its tools. Nested Edit fields map from old_text/new_text back to the
native schema's oldText/newText. Structured replies map back to snake case.
Unlisted effects, including Bash in this configuration, are unavailable.

--eyg-only or PI_EYG_ONLY=1 hides other tool declarations from the model;
they remain callable as effects. The description lists the effects its policy
allows and includes the context readme and syntax guide.

`perform Task({agent: "reader", prompt: "Read fruit.txt", policy: {read: Pass}})`
starts an in-process pi-agent-core Agent whose only tool is EYG. The child
policy restricts its parent's, or a policy explicitly configured for that named
agent. The closure keeps this policy on every subsequent child call. Nested
model usage, including cache tokens and costs, is added to the outer EYG tool
result. Abort signals are forwarded and their listener is removed afterward.

Escalate has the same request shape, replacing the inherited policy after
explicit UI confirmation. Without an interactive UI or approval, it starts no
subagent. The [policy guide](./harness_policies.md) explains gates, imports and
the boundary between path rules and filesystem confinement.

For the earlier shell-only integration, load dist/bash_only.mjs instead.
It permits one EYG executable invocation through the bash tool and rejects
shell operators, expansions and unclosed quotes. Single-quoted EYG source can
contain its own punctuation. This level leaves the CLI's effects unrestricted;
the policy extension supplies per-effect gates.

The package tests exercise the pinned SDK, native callbacks, denied operations, inherited child policies and tool routing without calling a model service.
