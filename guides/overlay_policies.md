---
name: Overlay policies
description: Allow or mock effects in an overlay agent.
---

# Overlay policies

An overlay configuration has a `context` and a `policy`. A policy contains one
gate function for each required effect the host checks. A missing field is a
configuration error. Optional `Acquire` and `Mount` gates stay unavailable when
omitted. Effects that do no IO, such as `Random` and `DecodeJSON`,
are not checked. The runtime calls the gate before performing an effect.

A gate returns:

- `Pass(input)` to perform the effect, the input can be changed.
- `Mock(result)` to return a value without performing it.

Mocking a refusal, i.e. `Mock(Error("read-only session"))` for `write_file`,
lets the program handle it as a normal file error.

Allow Fetch while denying file writes, starting from a helper policy in the
[overlay package](../eyg_packages/overlay/README.md) that has every field and
overwriting the fields to change:

```eyg
let {policy} = import "./eyg_packages/overlay/index.eyg"

{
  fetch: (request) -> { Pass(request) },
  write_file: (_) -> { Mock(Error("read-only session")) },
  ..policy.read_only(["/project"])
}
```

The CLI checks gate types against its effects when the session starts. A
browser session gates its own effects, including Artifact, Show and Puppet.
File effects are only available in a session with a workspace, where they are
gated too. Without a policy a browser session performs every effect.

See the [overlay package](../eyg_packages/overlay/README.md) for path
restrictions and the other helper policies, and the
[overlay README](../packages/overlay/README.md) for the effect rules of each host.
