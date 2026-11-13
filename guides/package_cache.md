---
name: Persistent CLI package cache
description: Reuse content-addressed hub modules across CLI processes and keep the last fetched release pages for offline use.
---

# Persistent CLI package cache

CLI runs keep hub responses under `$XDG_CACHE_HOME/eyg/hub/<origin-sha256>`
(or the platform's default cache directory). The complete hub origin, including
scheme and port, identifies each store.

Module files are addressed by their EYG CID. Reads verify the bytes again;
corrupt files are refetched. Successful module hash checks and ledger-page
decoding happen before a response is stored. Cache write failures leave the
network result usable. Package values are still checked and evaluated purely
by the normal in-memory package cache.

New processes refresh release pages online. If the network fails, previously
stored pages allow offline resolution. `@name` therefore uses the last available
release mapping when offline. [Full pins](./syntax.md#named-packages) retain an
exact module choice. This cache adds no publisher authentication to the hub
protocol. Sealed environments use their retained module store independently.

## Check across processes

Build the CLI from `packages/gleam_cli` with `gleam run -m compile`. Then from
`packages/tracing` run:

```sh
gleam run -m tracing/cache_check
```

The Gleam check starts a repository hub fixture, calls the standalone CLI in
two independent processes, stops the hub, and calls it again offline. It checks
the same pinned expression returns `42` every time, with module reuse on the
second run. `EYG_BIN` selects another compiled CLI binary.

Each embedding can choose its own cache owner. This CLI store keeps verified
module bytes and release-page responses for rebuilding values in a new process.
On the Pi this cache lives on the
mounted SD card and can survive reboot.
