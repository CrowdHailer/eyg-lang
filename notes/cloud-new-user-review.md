---
name: Cloud new user review
description: What a new user found unclear arriving at the cloud's product page, and what was simplified.
date: 2026-11-12
---

A review of the product page at `/`, the web shell and the example workspace, read as someone new to EYG.
Each item was implemented in the commit that introduced the feature it changes.

| Unclear or complicated | Change |
| --- | --- |
| "Shell" means a channel's policy, the web UI and a person's policy | A glossary on the product page defines shell as the policy a program runs with, and workspace, channel, connection, trigger and binding |
| Trigger scripts were EYG source inside a string, with escaped quotes | Scripts are functions of the event, captured like patterns. Source text still works |
| Quick trigger cards said a connection was needed without saying if it existed | Signed in, each card reads `Connections` through the API and says which connection is ready or what to add |
| The workspace was a free text field | A list read with `Workspaces` |
| "Open the shell" led to a sign in that silently made the first person admin | The button says sign in, the sign in page and product page explain the admin and that names are not authentication |
| Get started mixed using this cloud with running your own | Separate sections, running your own includes saving the model key |
| `workspace.eyg`'s `channel` function nested a `match` per channel | `cloud.channels.named` takes a list of `{name, config}` and a function for the rest |
| A trigger added before a channel's first event dropped its configured triggers | Configured triggers are installed before any trigger operation |
| Installing a trigger replied `Ok({})` | Generated programs list the channel's triggers after adding one |
| "Admin" link shown to people who are not admins | Named Configuration, the page works for everyone with their shell's operations |

Left for later, they need larger changes:

- Patterns need a catch all `| (_) -> { False({}) }`. Programs may import helpers stored in the session file system; imports use the channel's `ReadFile` gate and never the host file system.
- Connections and crons apply after a restart.
- Signing in by name is not authentication.
