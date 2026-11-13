---
name: Web shell
description: Run EYG with a user policy or a channel policy and private in-memory files.
---

`/shell` runs programs on the cloud through a Lustre server component. Sign in at
`/login`; the first user is the administrator. This name-only login needs external
authentication before public use. Other users select a policy from `cloud.eyg`:

```eyg
let pass = (input) -> { Pass(input) }
{
  workspaces: [{name: "example", file: "./workspace.eyg"}],
  shells: {
    pure: cloud.mock_all,
    observer: {workspaces: pass, channels: pass, ..cloud.mock_all}
  }
}
```

The unbound shell uses the user's policy. The [configuration API](./api.md)
reads and edits actor-held workspace settings and secrets.

```eyg
perform Connections("example")
```

`Bind` selects a channel's policy and reply destination for subsequent programs:

```eyg
perform Bind({workspace: "example", channel: "dev"})
```

The user's files stay private across bindings. Binding does not expose the
channel agent's files. The `bind` gate decides which targets are allowed; the
Unbind button returns to the user's own policy.

Every command starts with fresh lexical scope. Session files and command reports
remain in memory between commands. They are not saved to host files or restored
after all state owners stop. The browser keeps its cell display and binding.
One central actor runs all web programs and agent turns serially, so a long turn
delays later commands. Cluster replication remains separate work.
