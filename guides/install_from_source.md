---
name: install from source
description: How to compile and install the eyg CLI from source.
---

Manage EYG projects with a self-contained binary.
The source is in [`packages/gleam_cli`](../packages/gleam_cli/). 

To install without the Gleam and Bun toolchains, follow the
[install a prebuilt binary](./install_prebuilt.md) guide instead.

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
gleam run -m install
```

The Gleam installer compiles with Bun and uses `sudo install` to place the
executable at `/usr/local/bin/eyg`.

If `sudo` isn't available, for example inside a sandbox or a dev container,
compile first and copy by hand:

```sh
gleam run -m compile
cp dist/eyg "$HOME/.local/bin/eyg"   # or anywhere on your $PATH
```

Cross-compile by passing a Bun target and output path, for example:

```sh
gleam run -m compile -- bun-linux-arm64 dist/eyg-linux-arm64
```

The build reads an exact `gleam_cli-*` tag for the version, otherwise it reports
`dev`. Compilation and version selection are Gleam; the Bun API bindings are
in `plinthx`. The Pi builder uses this same cross-compilation entrypoint.

## Verify

To verify inline source execution, run:

```sh
eyg eval -c '!int_add(1, 1)'
```

The value `2` should be printed.
