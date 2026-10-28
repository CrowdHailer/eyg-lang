---
name: Fetching EYG packages with Nix
description: Acquire complete pinned EYG module graphs and use them as fixed-output Nix inputs.
slug: nix-fetcher
---

# Fetching EYG packages with Nix

EYG fetchers acquire immutable contents before execution. `Acquire` returns
an artifact receipt; `Mount` puts retained contents in a private filesystem.
The [sandbox guide](sandbox.md) covers Git/HTTP inputs and ordered replay.

`eyg fetch-package` acquires an EYG module and its transitive code dependencies.
It verifies every CID, deduplicates blocks and writes a portable bundle, without
evaluating the code. Roots and dependencies must use `#<cid>` or the fully pinned
`@name:version:<cid>` form. The CID identifies the code; this fetcher does not
refresh or authenticate the publisher ledger behind the name/version label.

```sh
# packages/gleam_cli, using the CLI from this checkout
gleam run -- fetch-package '#<module-cid>' package.json
gleam run -- sandbox package package.json environment.json
gleam run -- sandbox run environment.json entry.eyg runs
```

`sandbox package` prepares the downloaded closure offline. `entry.eyg` evaluates
the package value. Nested pinned release metadata is retained for offline imports.
The environment's module cache is loaded once and shared across private forks.

## Nix adapter

[nix/fetch-eyg.nix](../nix/fetch-eyg.nix) is the minimal native Nix adapter.
All acquisition and CID validation are Gleam CLI logic. Pass a Nix-packaged EYG
CLI, including its runtime dependencies, as `eyg`:

```nix
let
  fetchEyg = import ./nix/fetch-eyg.nix { inherit eyg; };
in fetchEyg {
  reference = "#<module-cid>";
  hash = "sha256-<base64-hash-of-package.json>";
  hub = "https://eyg.run";
}
```

The result is the complete bundle JSON. Obtain its hash with
`nix --extra-experimental-features nix-command hash file --type sha256 package.json`.
Nix checks the **flat SHA-256 of the bundle file**;
the EYG CID checks canonical DAG-JSON code, and the bundle includes every
dependency. These hashes identify different representations and are not
interchangeable. Output ordering is deterministic and excludes timestamps and
the mirror URL.

| EYG acquisition | Nix fetcher |
| --- | --- |
| Captures a tree/blob or module graph into a verified block store. | Builds a fixed-output derivation and checks the supplied output hash. |
| An unlocked branch/URL creates an observation; retain its receipt or require an expected CID. | A fetcher requires a fixed hash; changed bytes fail the build. |
| Mounts are private; execution, model calls and external observations can be replayed. | Store inputs are immutable; fetching alone does not reproduce model or service interactions. |
| Roots identify canonical EYG DAG-JSON and its referenced blocks. | Flat hashes identify file bytes; recursive hashes identify a NAR filesystem representation. |

See Nix's [fixed-output attributes](https://nix.dev/manual/nix/2.35/language/advanced-attributes.html)
and [fetcher reference](https://github.com/NixOS/nixpkgs/blob/master/doc/build-helpers/fetchers.chapter.md).

## Checked integration

The Gleam check uses real Nix 2.34.6 in Docker. It verifies a three-module graph,
rejects the wrong output hash, stops its hub fixture and checks the cached output.
From `packages/gleam_cli`, build the current Linux CLI:

```sh
gleam build
bun build build/dev/javascript/eyg_cli/eyg_cli.mjs --compile \
  --footer='main();' --outfile=/tmp/eyg-nix-builder/bin/eyg
```

Then from `packages/loam`:

```sh
EYG_NIX_BIN=/tmp/eyg-nix-builder/bin/eyg \
  gleam run -m loam/nix_integration --runtime bun
```

This Linux Docker fixture supplies the host binary's dynamic libraries and
disables Nix's nested OS sandbox. Production callers should pass a CLI derivation
with its Nix runtime dependencies. The check removes its own container and server.
