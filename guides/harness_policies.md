---
name: Policies for embedded harnesses
description: Gate computer and host effects with composable EYG functions.
---

# Policies for embedded harnesses

## Integration levels

| Level | Boundary | Checked implementation |
| --- | --- | --- |
| 1 | Choose EYG as the scripting executable; CLI effects remain unrestricted | Pi's optional shell-only adapter |
| 2 | Add an embedded EYG tool | OpenCode plugin and Pi extension |
| 3 | Gate every effect performed by that tool | Shared runtime and configuration |
| 3.a | Restrict children or approve an explicit replacement policy | Task and Escalate adapters |
| 4 | Route the complete host tool set through EYG | Pi --eyg-only; native OpenCode dispatcher |

Other action paths retain their host permissions until they are included in
the boundary. The [OpenCode](../blog/eyg-in-opencode/README.md) and
[Pi](../blog/eyg-in-pi/README.md) articles explain the integration choices.

## Shared runtime

[opencode_plugin](../packages/opencode_plugin/) provides the shared Gleam
runtime. A trusted configuration returns policy, optional context and optional
named agent policies. Agent code gets context in scope; each run starts fresh.

```eyg
{
  policy: {
    read_file: Pass,
    write_file: (_) -> { Mock(Error("read only")) }
  },
  context: {readme: "Inspect files and propose changes."}
}
```

Each field is an effect's snake case name: ReadFile uses read_file and Task
uses task. Pass(lift) continues with that request; Mock(lower) resumes with a
reply without calling the host. A missing gate makes the effect unavailable.
DecodeJSON, EYGParse, Flip, Hash and Random are available without gates.
StandardOut and StandardError are captured unless explicitly gated. Exit is
unavailable; StandardIn has no input in this host.

Gates are pure functions. Resolve any imported helpers while loading the
trusted configuration. A gate cannot perform effects or load new references.
The configuration itself executes as trusted host code and may use IO.

`restrict(parent, child)` retains only fields present in both. For a request,
the child gate runs first, followed by the parent gates. Rewritten file paths
are normalized to absolute paths before each gate. A Mock ends the chain,
since it performs no host operation. A named agent's configured policy can
serve as its starting policy; adapters choose when explicit escalation is allowed.
An omitted gate stays unavailable in descendants, including gates for effects
that are normally open by default. A child can also gate an open default effect.

Relative program imports use the read_file gate for every file, including
nested imports. A rewritten module path anchors further imports to its new
location. Module loading is pure; functions it defines may perform effects
later under the caller's policy. File policies compare normalized paths;
filesystem confinement uses the separate [sandbox](./sandbox.md).

Host effects use `host(label, request_description, reply_description, callback)`.
The same gates run before their callbacks. Requests cross as native objects,
arrays and booleans; Some unwraps, None becomes null, and other tags become
single-field objects. The callback also receives the raw EYG value, allowing
Task to retain policy functions. Replies resume as Ok(value), and thrown or
rejected callbacks resume as Error(message). These host type descriptions are
for the model; runtime conversion and the host's own validation check arguments.

`run(code, policy, context, directory, hosts)` returns a report containing
success, output, final value and observed effect labels. The explicit directory
anchors file operations. Hub package loading owns a separate cache inside each
run, as in the other embedding APIs; retaining configuration retains its loaded
helpers and values. The standalone core includes no opencode or pi SDK.

From packages/opencode_plugin, run `gleam run -m build`, then `gleam test` and
`gleam test --runtime node`. The checks cover actual file reads, mocked writes,
denial, child restrictions, normalized rewrites, nested imports, pure gates,
host failures and a native consumer of the built dist/core.mjs.

`opencode_plugin/tools` adapts host tool schemas. Tool read becomes effect Read;
mcp__github__search becomes McpGithubSearch. EYG arguments use snake case names,
including nested edit records, and argument maps them back using the original
schema. Null object fields are omitted. Structured replies use snake case names
recursively; native byte arrays pass through unchanged. The model-facing type
description marks optional fields with ?, selects the first anyOf alternative
and describes numeric tool fields as Integer, matching EYG's numeric values.

`opencode_plugin/router` wraps a host's tool dispatcher. Only exposes one EYG
tool, Gate keeps direct tool calls and runs each through the same policy path,
and Off returns the original tools. The host supplies each tool's schema and
normal execution callback, preserving its own validation, permissions and events.
This is the routing layer; installing it into a host needs that dispatcher hook.

A Task callback reports the child session id before running it. The router
stores the requested restricted policy against that id, so later calls keep
it even when looking up the parent would give a broader policy. Named agent
policies are trusted starting points. Recreate the router after configuration
changes. Missing or cyclic parent ancestry fails execution.
