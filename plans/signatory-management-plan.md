# EYG CLI — Signatory Management & Publishing: Implementation Plan

## Overview

This document covers everything needed to add signatory management and package
publishing to the `gleam_cli` package. The work breaks into five areas: filesystem
layout, argument parsing, new command modules, extensions to the internal client,
and supporting crypto/key utilities.

---

## 1. Filesystem Layout

Define and document the two directories the CLI will read and write.

### Config — `~/.config/eyg/signatories/<name>.json`

One file per principal this machine can sign on behalf of. Private material.
Should be created with restricted permissions (`0600`).

```json
{
  "name": "peter-saxton",
  "key_id": "z6Mkf...",
  "principal_cid": "bafyrei...",
  "private_key": "<base32-encoded raw private key bytes>"
}
```

- `name` — human label, matches the filename stem, local only
- `key_id` — base32-encoded DER public key, used as the `key` field in all hub entries
- `principal_cid` — CID of the first entry in this principal's signatory chain on the hub
- `private_key` — base32-encoded raw Ed25519 private key bytes

### Cache — `~/.cache/eyg/principals/<principal-cid>.json`

Cached `ArchivedEntry` array for a principal's signatory history, newest last.
Reconstructible from the hub at any time — safe to delete.

```json
{
  "entries": [ ...ArchivedEntry... ],
  "cursor": 42
}
```

`cursor` is the highest `cursor` value seen, used as the `since` parameter on
incremental pulls.

---

## 2. `src/eyg/cli/args.gleam`

Add new variants to the `Args` type and extend `parse/1`.

```gleam
pub type Args {
  Run(file: String)
  Share(file: String)
  Fetch(cid: String)
  Publish(cid: String, package: String)
  SignatoryNew(name: String)
  SignatoryJoin(name: String, principal_cid: String)
  SignatoryAddKey(name: String, key_id: String)
  SignatoryStatus(name: String)
  SignatorySync(name: String)
  Fail
}

pub fn parse(args) {
  case args {
    ["run", file] -> Run(file:)
    ["share", file] -> Share(file:)
    ["fetch", cid] -> Fetch(cid:)
    ["publish", cid, package] -> Publish(cid:, package:)
    ["signatory", "new", name] -> SignatoryNew(name:)
    ["signatory", "join", name, principal_cid] -> SignatoryJoin(name:, principal_cid:)
    ["signatory", "add-key", name, key_id] -> SignatoryAddKey(name:, key_id:)
    ["signatory", "status", name] -> SignatoryStatus(name:)
    ["signatory", "sync", name] -> SignatorySync(name:)
    _ -> Fail
  }
}
```

---

## 3. New Command Modules

### `src/eyg/cli/publish.gleam`

Steps:

1. Parse the module CID from the string produced by `share`
2. Load the signatory file via `internal/signatories.load(name)`
3. Pull and validate the latest principal history from cache, refreshing from
   hub if stale, and check the local `key_id` is still active — fail with a
   clear message if not
4. Build the entry using `publisher.first` or `publisher.follow` depending on
   whether a previous package entry exists
5. Sign `publisher.to_bytes(entry)` using the local private key
6. Submit via `internal/client.submit_package`
7. Append the returned `ArchivedEntry` to the principal cache
8. Print `published <package> version <n> -> <cid>`

### `src/eyg/cli/signatory.gleam`

Four functions, one per subcommand:

#### `new(name, config)`

1. Generate a fresh Ed25519 keypair via `internal/crypto.generate()`
2. Derive `key_id` as base32-encoded DER public key
3. Build `signatory.first(key_id)` — the bootstrap intrinsic entry
4. Sign it with the new private key
5. Submit via `internal/client.submit_signatory`
6. Write `~/.config/eyg/signatories/<name>.json` with `principal_cid` from
   the returned `ArchivedEntry`'s `entity` field
7. Write initial history to `~/.cache/eyg/principals/<principal-cid>.json`
8. Print `created principal <principal-cid>\nsignatory: <name>\nkey: <key-id>`

#### `join(name, principal_cid, config)`

1. Parse and validate the principal CID string
2. Generate a fresh Ed25519 keypair
3. Derive `key_id`
4. Write `~/.config/eyg/signatories/<name>.json` with the given `principal_cid`
   but **do not submit anything to the hub**
5. Print:
   ```
   signatory file written: ~/.config/eyg/signatories/<name>.json
   key id: <key-id>

   To activate, run on an authorised device:
     eyg signatory add-key <existing-name> <key-id>
   ```

#### `add_key(name, foreign_key_id, config)`

1. Load `~/.config/eyg/signatories/<name>.json`
2. Pull fresh principal history from hub, update cache
3. Verify local `key_id` is still active in the history — fail clearly if not
4. Build `signatory.follow(..., AddKey(foreign_key_id), previous)`
5. Sign and submit
6. Append returned `ArchivedEntry` to cache
7. Print `key <foreign-key-id> added to principal <principal-cid>`

#### `status(name, config)`

1. Load `~/.config/eyg/signatories/<name>.json`
2. Pull fresh principal history from hub, update cache
3. Compute current active key set via `signatory.state(history)`
4. Print each active key, marking the local one:

   ```
   principal: bafyrei...
   active keys:
     z6Mkf...  ← this machine
     z6Mkg...
   ```

#### `sync(name, config)`

1. Load `~/.config/eyg/signatories/<name>.json`
2. Pull full history from hub using `since: 0`
3. Overwrite `~/.cache/eyg/principals/<principal-cid>.json`
4. Print `synced <n> entries for principal <principal-cid>`

---

## 4. `src/eyg/cli/internal/signatories.gleam` — new file

Handles all local signatory file and cache I/O. Keeps filesystem concerns out
of the command modules.

```gleam
pub type Signatory {
  Signatory(
    name: String,
    key_id: String,
    principal_cid: v1.Cid,
    private_key: BitArray,
  )
}

pub type PrincipalCache {
  PrincipalCache(entries: List(schema.ArchivedEntry), cursor: Int)
}
```

Functions to implement:

- `load(name) -> Result(Signatory, String)` — reads and parses
  `~/.config/eyg/signatories/<name>.json`, resolving config dir via
  `$XDG_CONFIG_HOME` or `~/.config`. Also accepts `$EYG_SIGNATORY` env var
  as a direct path override.
- `write(signatory) -> Result(Nil, String)` — serialises and writes, creating
  the directory if absent, setting file permissions to `0600`
- `load_cache(principal_cid) -> Result(PrincipalCache, String)` — reads
  `~/.cache/eyg/principals/<cid>.json`, returning an empty cache if absent
- `write_cache(principal_cid, cache) -> Result(Nil, String)` — writes cache,
  creating directory if absent
- `append_to_cache(principal_cid, entry) -> Result(Nil, String)` — loads,
  appends, writes back; updates `cursor`
- `config_dir() -> String` — resolves `$XDG_CONFIG_HOME/eyg` or `~/.config/eyg`
- `cache_dir() -> String` — resolves `$XDG_CACHE_HOME/eyg` or `~/.cache/eyg`

---

## 5. `src/eyg/cli/internal/crypto.gleam` — new file

Thin wrapper over the JS crypto API, matching the encoding conventions from
`hub/crypto.gleam` (base32-encoded DER public key as `key_id`, base32-encoded
raw signature bytes).

Functions to implement:

- `generate() -> Result(#(key_id: String, private_key: BitArray), String)` —
  generates an Ed25519 keypair, exports the public key to DER, encodes both
- `sign(payload: BitArray, private_key: BitArray) -> Result(String, String)` —
  signs and returns a base32-encoded signature string ready for the
  `Authorization: Signature <sig>` header
- `key_id_from_private(private_key: BitArray) -> Result(String, String)` —
  derives the `key_id` from stored private key bytes, used when loading a
  signatory file

The JavaScript crypto API (`SubtleCrypto`) will be called via Gleam FFI,
consistent with how the rest of the JS-target packages in this repo handle
crypto.

---

## 6. `src/eyg/cli/internal/client.gleam` — additions

Add these functions alongside the existing `share_module` and `get_module`:

- `submit_signatory(revision, signature, config)` — wraps
  `hub_client.submit_signatory`
- `submit_package(revision, signature, config)` — wraps
  `hub_client.submit_package`
- `pull_principal_history(principal_cid, since, config)` — pulls signatory
  entries for a given principal CID using the `entities` filter on
  `PullParameters`
- `pull_package_history(package, config)` — pulls existing package entries to
  determine `first` vs `follow` and get the `previous` entry

---

## 7. `src/eyg_cli.gleam` — wire up

Add imports for `signatory` and `publish` command modules and extend the
`case` in `main`:

```gleam
args.Publish(cid:, package:) ->
  publish.execute(cid, package, config())

args.SignatoryNew(name:) ->
  signatory.new(name, config())

args.SignatoryJoin(name:, principal_cid:) ->
  signatory.join(name, principal_cid, config())

args.SignatoryAddKey(name:, key_id:) ->
  signatory.add_key(name, key_id, config())

args.SignatoryStatus(name:) ->
  signatory.status(name, config())

args.SignatorySync(name:) ->
  signatory.sync(name, config())
```

---

## 8. `gleam.toml` — dependency

Confirm that `kryptos` (or the equivalent JS-target crypto package) is
available and added to dependencies. The hub server uses `kryptos/eddsa` on
the Erlang target. The CLI is JavaScript target, so the FFI shim for
`SubtleCrypto` needs to be either within `internal/crypto.gleam` directly or
sourced from an existing package already in the dependency tree.

Verify this before implementing `internal/crypto.gleam`.
