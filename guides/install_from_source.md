---
title: install from source
description: How to compile and install the eyg CLI from source.
---

Manage EYG projects with a self-contained binary.
The source is in [`packages/gleam_cli`](../packages/gleam_cli/). 
This CLI provides `eyg run`, `eyg compile`, `eyg repl` as well as commands
to share/publish code on the EYG hub.

## Prerequisites

| Tool | Used for |
|---|---|
| [Gleam](https://gleam.run) ≥ 1.7 | Compiles the Gleam source to JavaScript |
| [Bun](https://bun.com) | Package the JS into a single executable |

Install Gleam with these [instructions](https://gleam.run/install/)

Install bun with:

```sh
curl -fsSL https://bun.sh/install | bash
```

## Build and install

```sh
git clone https://github.com/CrowdHailer/eyg-lang.git
cd eyg-lang/packages/gleam_cli
./bin/install
```

The script runs `./bin/compile` an uses sudo to move that executable to `/usr/local/bin/eyg`.

If `sudo` isn't available, for example inside a sandbox or a dev container,
compile first and copy by hand:

```sh
./bin/compile
cp dist/eyg "$HOME/.local/bin/eyg"   # or anywhere on your $PATH
```

## Verify

```sh
eyg run packages/gleam_cli/examples/pure.eyg
```

You should see `2` (the script is `!int_add(1, 1)`).

To verify inline source execution, run:

```sh
eyg eval -c '!int_add(1, 1)'
```
