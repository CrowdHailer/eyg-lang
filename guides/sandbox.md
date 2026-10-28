---
name: Reproducible sandboxes
description: Prepare an immutable environment, fork EYG and Overlay executions, and replay them without the original host.
slug: sandbox
---

# Reproducible sandboxes

Build the CLI from this checkout until these commands are released. From
`packages/gleam_cli`, use `gleam run --` in place of `eyg` in the examples below.

A sandbox starts from an immutable environment, identified by a content hash.
It contains the whole selected filesystem, pinned code dependencies, explicit
environment variables, the hub origin, a clock, a random seed and a runtime
semantics version. Forks share immutable data and have private writes.

There is no fallback to the host filesystem or environment. Missing files are
ordinary filesystem errors. The same filesystem implements reads, listings,
metadata, directory creation, append and deletion.

## Prepare and run

Given `project/main.eyg`:

```eyg
let _ = perform WriteFile({path: "result.txt", contents: !string_to_binary("hello")})
perform StandardOut("created result.txt in the sandbox\n")
```

```sh
eyg sandbox prepare project main.eyg environment.json
eyg sandbox run environment.json main.eyg runs
```

Preparation mounts `project` at `/workspace`, pins the entry's transitive code
dependencies, and writes a self-contained environment bundle. Its parent output
directory must exist. Preparation excludes `.git`, `.eyg` and `.env.eyg` entries;
other files in the selected tree are inputs. Symlinks and special files fail
explicitly. Acquisition is limited to 10,000 entries, 64 MB and 128 levels.

Use a directory containing every relative import the entry needs. An import
outside the mounted tree fails. `@package` references are resolved during
preparation; execution uses those releases without refreshing the hub.

`run` executes an EYG block. Writes become part of the resulting environment;
`project/result.txt` on the host is never created. Output is captured and printed
when the run finishes. A failed run is saved and returns a nonzero CLI status.

## Overlay agents

Start with only an explicit configuration and acquire project inputs at runtime:

```sh
eyg sandbox start agent.eyg runs "Acquire master and inspect the repository" localhost git:example.com
```

This prepares `/workspace/.overlay.eyg` and its code dependencies, without copying
the host project directory. The configuration needs `acquire` and `mount` policy
fields to expose those operations to the agent. Relative imports not present in
this configuration-only environment fail; use `prepare` for a larger boot tree.

Or start from a prepared project:

```sh
eyg sandbox prepare project .overlay.eyg environment.json
eyg sandbox overlay environment.json .overlay.eyg runs "Summarise the notes" localhost
```

The configuration itself executes inside the sandbox. The example explicitly
allows live requests to `localhost`, for a local model server. Trailing host
arguments allow live requests to those hosts, for any HTTP method. Overlay's
own effect policies still run before the external broker.

No host environment variables or secret directories are inherited. Snapshot
files and explicitly supplied environment values are portable data. Keep
credentials outside them, for example in a credentialed model/API proxy.
Secret imports that cannot be stored are rejected during preparation.

## Replay, export and continue

Use the trace path printed by the run:

```sh
eyg sandbox replay runs/<id>.json
eyg inspect runs/<id>.json
eyg sandbox export runs/<id>.json portable.json
eyg sandbox snapshot runs/<id>.json next-environment.json
eyg sandbox run next-environment.json main.eyg runs
```

Full sandbox replay executes the configuration, model requests and tool programs.
It consumes external observations in order and checks the EYG journals, results,
terminal output and final environment identity. It needs no network or original
checkout. `eyg replay` remains the narrower, per-EYG-run journal replay command.

The run directory has a shared `blocks/` store. Trace files contain metadata and
root references; common blocks are written once. `export` produces the single
self-contained JSON file used by the browser debugger or another machine.
`snapshot` exports the output environment for subsequent execution.

## External observations

One broker handles HTTP and acquisition requests from programs, configuration and models:

- **Offline:** external requests are refused and the refusal is recorded.
- **Live:** perform requests to explicitly allowed hosts and record responses.
- **Replay:** consume the next recorded request/response; mismatch or unused
  observations fail verification.
- **Fork:** reuse an identical ordered prefix. At the first difference, discard
  the remaining prefix and switch to permitted live requests.

HTTP request fingerprints include scheme, host, port, method, path, query,
headers and body. Acquisition fingerprints include the tagged source descriptor
and expected artifact CID. HTTP requests themselves are not stored by the broker;
acquisition receipts retain source, resolved revision and a content reference.
Responses and failures are stored. Repeated identical requests can have different
responses: they are observations, not a request-keyed cache.

Pure operations such as hashing, parsing and JSON decoding always recompute.
Filesystem operations use the private tree. Arbitrary Git commands and key generation
are unavailable to sandboxed code. The trusted repository fetcher can invoke Git
outside the sandbox after broker authorisation. There are no simulated commits or
automatic point-in-time database queries.

## Fetchers

`Acquire` and `Mount` are separate effects because obtaining immutable input
and placing it in a private filesystem have different permissions and failure
modes. These general contracts cover Git trees and HTTP blobs without exposing
shell commands or adding an effect for each service.

`loam/acquire` provides host-side acquisition adapters:

| Fetcher | Result |
| --- | --- |
| `local` | a complete immutable filesystem tree |
| `http` | an immutable binary, optionally checked against an expected CID |
| `repository` | a Git revision materialised as an immutable tree, optionally checked against an expected tree CID |

The [Nix fetcher guide](nix_fetcher.md) compares these contracts and describes
the Gleam package-graph fetcher and its native fixed-output Nix adapter.

These preparation helpers return `glasshouse/bundle.Bundle`. The runtime adapter
`acquire.perform` also returns provenance in a `Receipt`. Git is needed only for
live repository acquisition, not replay. Runtime acquisition creates and cleans
its own host scratch directory; the lower-level `repository` helper accepts an
unused caller-supplied checkout path.

An acquisition without an expected CID resolves/locks an input. Retain that
bundle or verify subsequent acquisitions against its CID. A mutable URL or branch
name alone does not provide reproducibility. Local capture is not an atomic
snapshot of a concurrently changing host tree; the resulting captured tree is
the immutable input.

### Runtime acquisition and mounting

```eyg
let result = perform Acquire({
  source: Git({url: "https://example.com/team/project.git", ref: Some("master")}),
  expected: None({})
})
match result {
  Ok(receipt) -> { perform Mount({root: receipt.root, path: "repo"}) }
  Error(reason) -> { Error(reason) }
}
```

`Acquire` returns `Result({root: String, resolved: String}, String)`. For Git,
`resolved` is the exact commit; `root` identifies the captured file tree, not a
Git object. `ref: None({})` selects the repository's default HEAD. `Http({url})`
acquires a binary artifact, with the requested URL as `resolved`. An optional
`expected: Some(cid)` verifies the captured artifact's EYG CID.

Every live branch acquisition resolves again. Two identical calls can observe A
then B; replay returns their original receipts and complete trees in that order.
HTTP/model calls and acquisitions share one journal cursor. No remote or Git
installation is needed to replay an exported recording.

Runtime Git grants are `git:<host>` for HTTPS repositories and
`git:file:<absolute-path>` for an exact local repository. HTTP acquisitions use
the ordinary host grant. Authority checks apply before the live adapter is called.
SSH, symlink entries and submodules are not supported by this fetcher.

`Mount({root, path})` returns `Result({}, String)`. It accepts only retained
artifacts, requires an existing parent and refuses any existing destination.
Choose another path or explicitly delete the old one before replacing it. Edits
to a mounted tree do not alter the original artifact or other mounts. Acquired
roots remain available in exported output environments even if never mounted.

Imports are pinned before a tool program runs: acquire/mount a code tree in one
tool call, then import from it in a subsequent call.

## Evaluate variants

`eyg evaluate <trace> <variants.eyg>` requires a sandbox trace with a complete
input environment. For example:

```eyg
{
  hosts: ["localhost"],
  variants: [
    {name: "same", files: [], prompts: None({})},
    {name: "brief", files: [{path: "README.md", contents: "Be brief."}], prompts: None({})}
  ]
}
```

Every variant forks the sealed inputs. The initial clock and seed are the same
across variants; the variant name does not affect execution. Changed external
requests require an allowed live host, including changed model requests.
The cohort compares complete input/output trees, even for files overwritten
without a prior read, and distinguishes replayed from live model tokens.

Older host-observation traces remain inspectable and replayable with `eyg replay`,
but cannot be evaluated as complete environments. They must be recorded again
using `eyg sandbox`; unknown historical state is never guessed from today's disk.

## Embedding and resource bounds

- `loam/environment.open` loads a prepared environment; `virtual.fork` is O(1).
- `eyg/cli/sandbox.ready` validates/preloads an environment once, and `fork` runs
  repeated EYG blocks or agents against that shared prepared value.
- `eyg/interpreter/process.slice` returns after a specified reduction budget,
  even without IO. Retain a yielded process to resume it; drop it to cancel it.
- The synchronous interpreter entry points stop after 1,000,000 reductions per
  uninterrupted execution/resumption. The sandbox additionally limits system
  effects to 100,000, external requests to 1,000, writes to 64 MB, captured output
  to 1 MB, and each ordinary HTTP request/response body to 8 MB. Acquisition
  capture and unique retained payloads have a 64 MB limit; mounting counts the
  artifact's logical file bytes against the write budget.
- `Now` reads the virtual clock (initially zero); `Sleep` advances it. Recording
  timings do not advance the clock. Randomness is a per-fork seeded stream.

These are reduction and IO budgets, not a hard JavaScript heap bound or a
preemptive native-code sandbox. A builtin is one indivisible reduction, network
bodies are checked after receipt, and model histories still store full requests.
Git capture limits do not bound native clone transfer size or execution time.
Worker/process heap limits, transport deadlines/streaming limits, crash-safe
incremental journals and a hosted multi-tenant scheduler are further platform work.

Run the fork benchmark from `packages/loam`:

```sh
gleam run -m loam/sandbox_bench --target javascript --runtime bun
```

It retains 1,000 forks of a 4 MiB input, executes an EYG write in each, verifies
that every fork references the same input object, and reports retained heap and
elapsed time. It also checks that a pure runaway yields while another process
completes. This measures sandbox execution overhead, not model throughput.
