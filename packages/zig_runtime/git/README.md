# Native Git through EYG effects

`native.eyg` is the EYG facade for the Zig runtime's local `GitQuery` effect.
Storage decoding and writes use Zig's standard library; the implementation never
spawns Git. Git is an independent verifier in the Python tests.

The reference implementation is `real-world` at
`f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9`, particularly `dark/git/{read,write,config}.eyg`.
This is a native backend with an EYG interface. It is not a claim that those
EYG modules are executed unchanged or that every Git API is identical.

## Use in the TUI

Launch `zig-out/bin/eyg` from the repository root, paste this program and press
Enter. Bindings remain available for later queries:

```eyg
let git = import "packages/zig_runtime/git/native.eyg"
let repo = "/absolute/path/to/eyg-lang"
let subjects = (rows) -> {
  !list_fold(rows, [], (commit, found) -> { [commit.subject, ..found] })
}
subjects(git.query({repo, contains: "parser", author: "Peter", limit: 3}))
```

Query options are ordinary records. `ref` defaults to `HEAD`; hexadecimal SHA-1
IDs, local branches, full refs, tags and `~N`/`^N` parent suffixes are accepted.
`path` selects commits where that committed path's object ID differs from the
first parent, including deletions. `since`/`until` are inclusive Unix **seconds**
from the committer header. `contains` and `author` are case-sensitive substrings.
`limit` defaults to 20 and bounds returned records; `scan_limit` defaults to
10,000 and bounds visited commits. A bounded query can stop before finding all
matches. Traversal follows first parents, without date sorting.

```eyg
subjects(git.query({repo, path: "guides/syntax.md", limit: 3}))
subjects(git.query({repo, author: "Peter", since: 1793130000, until: 1793220000, limit: 3}))
git.show(repo, "HEAD~2", "README.md")
git.remotes(repo)
```

`history(repo, limit)`, `head`, `resolve`, `commit`, `object`, `tree`, `show`,
`remotes` and `query` are exported. The facade unwraps `Ok` replies and performs
`Abort` on failures. Object/show results contain `{kind, bytes, encoding, size}`:
`bytes` is a **base64 string**, `encoding` is `"base64"`, and a `text` field is
included for valid UTF-8 bytes. This transport representation differs from the
binary-valued `real-world` facade. History records retain `id`, `tree`, `parents`,
`author`, `committer`, `subject`, `message` and add a numeric `timestamp`.

## JSONL interface and writes

Run `eyg --protocol` and send one JSON object per line. Every request has
`{"op":"git","repo":"/absolute/checkout","action":"..."}`. The action defaults
to `query`. Errors return `{"error":"Name"}`.

| Action | Additional fields | Result |
| --- | --- | --- |
| `head` | none | `{branch,id}` |
| `resolve` | `ref` | SHA-1 string |
| `object` / `commit` / `tree` | `id` or `ref` | object / commit / entries |
| `history` / `query` | options above | commit records |
| `show` | `ref`, `path` | object bytes |
| `remotes` | none | local remote records |
| `init` | `branch` (default `main`) | absolute repository path |
| `write_blob` | `text` or base64 `bytes` | object ID |
| `write_object` | `kind`, `text` or base64 `bytes` | object ID |
| `write_tree` | `entries:[{name,mode,id}]` | tree ID |
| `commit_tree` | `tree`, `parents`, `author`, `committer`, `message` | commit ID |
| `snapshot_tree` | `files:[{path,mode,text/bytes}]` | tree ID |
| `update_ref` | `ref`, `id`, `expected` | published ID |
| `create_branch` | `name`, `id` | published ID |
| `commit_snapshot` | `files`, `ref`, `expected`, identities, `message` | `{id,tree}` |

An identity is `{name,email,timestamp,timezone}`; timezone is `+0000` or similar.
An absent/JSON-null `expected` means the ref must be absent; an existing tip
requires its SHA-1 string. `commit_snapshot` uses the expected tip as its parent
unless `parents` is supplied. A snapshot is the **complete intended tree**.
Writes create objects/refs and do not update the index or working-tree files.
They can also be requested from EYG with `git.query({action: "write_blob", ...})`.

Tree entries are validated and sorted in Git's byte order, including the
trailing slash comparison for directories. Ref publication locks `packed-refs`
then the branch, checks the logical old value, fsyncs the new ref and atomically
renames its lock. Existing locks are preserved. Writers must cooperate with Git's
lock convention. A crash can leave locks or unreachable objects; there are no
reflogs, directory fsync or multi-file crash transactions.

## Libraries and implementation review

- `src/git.zig`: loose objects, v2 pack indexes, 64-bit offsets, OFS/REF delta
  reconstruction, refs, linked worktrees, trees, commits and queries. Reuses
  `std.compress.zlib` and `std.crypto.hash.Sha1`. Every requested object ID and
  index checksum is verified. Pack data checksums are not scanned in full.
- `src/git_write.zig`: reuses the standard zlib encoder (`.fast`), SHA-1,
  filesystem locks, fsync and rename. No C zlib or OpenSSL is necessary for the
  measured workload. A libgit2 binding would remove format code but add an ABI,
  build and audit dependency; it was not used.
- `src/git_config.zig`: a small repository-local parser preserves repeated URLs,
  quoted subsection case, escapes and continuations. It does not resolve global
  configuration, includes, URL rewrites or environment overrides.

The decoded-object cache is scoped to one Repository/request. It caps retained
cache entries at 512 and accounted bytes at 16 MiB, including delta bases. This
**does not bound total arena memory**: response data, uncached objects, temporary
buffers and query metadata live until the caller releases the arena. Mutable
HEAD, refs and config are always read afresh.

SHA-256 repositories, object alternates, shallow boundaries, network transport,
index/status, diff, checkout and merge are unsupported. Delta recursion is capped
at 64, objects at 64 MiB and indexes at 128 MiB. JSON metadata requires UTF-8;
object bytes remain lossless through base64. Large filtered scans and synchronous
fsync writes can exceed 10 ms; the UI must schedule those operations if strict
input responsiveness is required.

## Verify and benchmark

With Zig 0.14.1, from the repository root:

```sh
zig build-exe -O ReleaseFast --dep git -Mroot=packages/zig_runtime/git/driver.zig \
  -Mgit=packages/zig_runtime/src/git.zig -femit-bin=work/git-native
python3 packages/zig_runtime/git/verify_native.py
python3 packages/zig_runtime/git/verify_writes.py
python3 packages/zig_runtime/git/benchmark.py
```

The standalone driver wraps each answer with `result` and `duration_ns`; the
integrated binary returns the raw result. For integrated verification pass
`--binary packages/zig_runtime/zig-out/bin/eyg --protocol`.

Read verification generates 100 seeded binary blobs, checks each loose and packed
against Git, generates 40 commits, and forces both delta formats using a valid
hand-built pack. It also checks linked worktrees, path/message/author queries,
mutable refs, truncated packs and index checksums. Write verification checks
hashes, Git tree order, nested snapshots, fsck, stale tips, owned locks and a
simultaneous compare-and-swap race.

`benchmark.py` compares every returned history ID to Git. Its native roundtrip
includes JSON, fresh repository/index setup, decompression, SHA-1 validation and
full structured records. Its `real-world` comparison uses a binary actually built
from the pinned checkout; it reports cold decoded-cache, warm decoded-cache and
process time separately. OS disk caches are warm. Results go under
`work/git-native-verification`; no universal latency or fastest-possible claim is
inferred from one machine.

`tests/record_git.py` records a real PTY session, verifies visible query results,
and exports an asciinema cast plus MP4. The MP4 renders that captured terminal
stream; it is not a mock TUI animation.

## Effect boundary rationale

The runtime also exposes general `Inflate` and existing `Hash` effects, so an
EYG decompressor or Git implementation can use native byte kernels. The new
`GitQuery` effect is a local object-database capability shared by CLI and TUI. It
is explicit in source, handler-replaceable and useful for structured repository
inspection and atomic local writes; it is not a shell-command escape. A native
backend was chosen after measuring the pinned EYG implementation's query cost.
This adds a platform capability rather than claiming to preserve a pure-EYG Git
implementation unchanged.
