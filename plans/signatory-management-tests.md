# EYG CLI — Signatory Management & Publishing: Test Plan

Tests are grouped by module. Where a test requires hub interaction, use a test
double for `client` unless the test is explicitly an integration test.

---

## `eyg/cli/args_test.gleam`

### `parse` — signatory subcommands

- `["signatory", "new", "peter-saxton"]` parses to `SignatoryNew("peter-saxton")`
- `["signatory", "join", "work", "bafyrei..."]` parses to
  `SignatoryJoin("work", "bafyrei...")`
- `["signatory", "add-key", "peter-saxton", "z6Mkf..."]` parses to
  `SignatoryAddKey("peter-saxton", "z6Mkf...")`
- `["signatory", "status", "peter-saxton"]` parses to
  `SignatoryStatus("peter-saxton")`
- `["signatory", "sync", "peter-saxton"]` parses to
  `SignatorySync("peter-saxton")`
- `["signatory"]` with no subcommand parses to `Fail`
- `["signatory", "new"]` with no name parses to `Fail`
- `["signatory", "join", "work"]` with no principal CID parses to `Fail`
- `["signatory", "unknown", "foo"]` parses to `Fail`

### `parse` — publish

- `["publish", "bafyrei...", "my-package"]` parses to
  `Publish("bafyrei...", "my-package")`
- `["publish", "bafyrei..."]` with no package name parses to `Fail`
- `["publish"]` with no arguments parses to `Fail`

---

## `eyg/cli/internal/signatories_test.gleam`

### `load`

- Returns `Error` with a clear message when the file does not exist
- Returns `Error` when the file exists but is not valid JSON
- Returns `Error` when the JSON is valid but missing the `key_id` field
- Returns `Error` when the JSON is valid but missing the `principal_cid` field
- Returns `Error` when `principal_cid` is present but not a valid CID string
- Returns `Error` when `private_key` is present but not valid base32
- Returns `Ok(Signatory)` with all fields correctly decoded for a well-formed file
- `$EYG_SIGNATORY` env var overrides the default path

### `write`

- Creates the signatories directory if it does not exist
- Writes a file that `load` can subsequently read back with identical values
- Overwrites an existing file without error

### `load_cache`

- Returns an empty `PrincipalCache` (entries: [], cursor: 0) when no cache
  file exists, rather than an error
- Returns `Error` when the cache file exists but is malformed JSON
- Returns `Ok(PrincipalCache)` with entries and cursor correctly decoded

### `write_cache` and `append_to_cache`

- `write_cache` creates the principals cache directory if it does not exist
- A cache written by `write_cache` can be read back by `load_cache` with
  identical entries and cursor
- `append_to_cache` on a missing cache creates a new cache with one entry
- `append_to_cache` on an existing cache adds the entry at the end
- `append_to_cache` updates the cursor to the appended entry's cursor value
- Appending the same entry twice results in two entries (no deduplication)

### `config_dir` and `cache_dir`

- `config_dir` returns `$XDG_CONFIG_HOME/eyg` when `XDG_CONFIG_HOME` is set
- `config_dir` returns `~/.config/eyg` when `XDG_CONFIG_HOME` is not set
- `cache_dir` returns `$XDG_CACHE_HOME/eyg` when `XDG_CACHE_HOME` is set
- `cache_dir` returns `~/.cache/eyg` when `XDG_CACHE_HOME` is not set

---

## `eyg/cli/internal/crypto_test.gleam`

### `generate`

- Returns a `key_id` that is valid base32
- Returns a `key_id` that round-trips through `public_key_from_der` without error
- Two calls to `generate` return different `key_id` values
- The returned `private_key` bytes have the expected length for an Ed25519 key

### `sign`

- A signature produced by `sign` can be verified by `hub/crypto.verify` with
  the corresponding `key_id`
- Signing the same payload twice with the same key produces the same signature
  (Ed25519 is deterministic)
- Signing different payloads with the same key produces different signatures
- Signing the same payload with different keys produces different signatures

### `key_id_from_private`

- Returns the same `key_id` as `generate` returned when the keypair was created
- Returns `Error` for an empty bit array
- Returns `Error` for a bit array that is not a valid Ed25519 private key

---

## `eyg/cli/signatory_test.gleam`

### `new`

- Writes a signatory file to the expected path after a successful hub response
- The written file contains the `principal_cid` from the hub's `ArchivedEntry`
  `entity` field
- The written file contains the correct `key_id` matching the generated keypair
- Writes an initial cache entry at the expected cache path
- Returns an `Error` message (does not write files) when the hub submit fails
- The entry submitted to the hub has `sequence: 1` and `previous: None`
- The entry submitted to the hub has `content: AddKey(key_id)`
- The entry submitted to the hub is signed with the newly generated private key

### `join`

- Writes a signatory file with the given `principal_cid`
- Does not make any HTTP requests to the hub
- The written file has no `cursor` or history — it is not yet active
- Returns `Error` when `principal_cid` is not a valid CID string
- The printed output includes the `key_id` and the `add-key` command to run

### `add_key`

- Submits an `AddKey` entry with the correct `foreign_key_id`
- The submitted entry's `previous` CID matches the latest entry in the local cache
- The submitted entry's `sequence` is one greater than the previous entry's
- Appends the returned `ArchivedEntry` to the local cache
- Returns `Error` with a clear message when the local `key_id` is not in the
  current principal history (key has been revoked)
- Returns `Error` with a clear message when the signatory file for `name` does
  not exist
- Pulls fresh history from the hub before submitting, not just the local cache

### `status`

- Pulls fresh history from the hub and updates the local cache
- Prints all currently active keys derived from the history
- Marks the local machine's `key_id` distinctly in the output
- Returns `Error` with a clear message when the signatory file does not exist
- Handles a principal with only one active key (the local one) without error
- Handles a principal with no active keys (all removed) gracefully

### `sync`

- Pulls history from the hub with `since: 0` (full reset)
- Overwrites the local cache entirely rather than appending
- Updates the `cursor` in the written cache to the highest value in the response
- Returns `Error` with a clear message when the signatory file does not exist
- Handles an empty response (no entries) without error

---

## `eyg/cli/publish_test.gleam`

### `execute`

- Returns `Error` with a clear message when the CID string is not valid
- Returns `Error` with a clear message when the local `key_id` is not active
  in the principal history — checked before any submission attempt
- Submits a `publisher.first` entry when no previous package entries exist
- Submits a `publisher.follow` entry when previous package entries exist, with
  correct `previous` CID and incremented `sequence`
- The submitted entry's `module` CID matches the input CID argument
- The submitted entry's `package` field matches the input package argument
- The submitted entry is signed with the local private key
- Appends the returned `ArchivedEntry` to the local principal cache
- Pulls fresh principal history from the hub before checking key status
- Returns a success message containing the package name and version number
- Returns `Error` with a clear message when the hub submit fails

---

## Integration Tests

These require a running hub instance (or a local test server) and should be
gated separately from unit tests.

- Full `signatory new` → `publish` flow succeeds end to end
- Full cross-device flow: `signatory new` on device A, `signatory join` on
  device B, `signatory add-key` on device A, `publish` on device B
- `publish` after key removal returns an appropriate error without submitting
- `signatory sync` after hub state has advanced brings the local cache up to date
- Two sequential `publish` calls for the same package produce version 1 and
  version 2 respectively
