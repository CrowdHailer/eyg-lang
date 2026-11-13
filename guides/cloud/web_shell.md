---
name: Web shell
description: Run EYG on the cloud from the browser, with your own policy or as a channel.
---

# The web shell

`/shell` is a shell in the browser. It is a [Lustre](https://hexdocs.pm/lustre) server component served by
[howdy](https://hexdocs.pm/howdy): programs run on the server and the page is updated over a WebSocket.

Sign in at `/login` with a name. The first person to sign in is the admin, their shell has every effect.
Everyone else chooses one of the `shells` in [`cloud.eyg`](../../examples/cloud/cloud.eyg) from the drop down at the top of the shell.

```eyg
let cloud = import "../../eyg_packages/cloud/index.eyg"
let shell = cloud.shell
let pass = shell.pass
{
  workspaces: [{name: "example", file: "./workspace.eyg"}],
  shells: {
    pure: shell.pure,
    observer: {workspaces: pass, channels: pass, bind: shell.bind_to(["random"]), unbind: pass, ..cloud.reject_all},
    online: {fetch: pass, now: pass, random: pass, flip: pass, standard_out: pass, ..cloud.reject_all}
  }
}
```

## Unbound

The shell starts unbound: it belongs to no workspace and runs programs with your shell policy.
From here the [configuration API](./api.md) reads and changes the cloud.

```eyg
perform Connections("example")
```

## Bound to a channel

`Bind` runs the following programs as a channel, with its `channel_shell` and its host.
They post to the channel, read and write the files the channel may, and read the events its connections log,
exactly what the channel's agent and triggers can do.

```eyg
perform Bind({workspace: "example", channel: "dev"})
```

```eyg
match perform Events("github") {
  Ok(events) -> { !list_fold(events, 0, (_event, n) -> { !int_add(n, 1) }) }
  Error(reason) -> { 0 }
}
```

Binding is an effect too, so policies decide who may bind where, `shell.bind_to(["random"])` allows only `#random`.
The Unbind button returns to your own shell. Each program runs on its own, variables do not carry over between them.
