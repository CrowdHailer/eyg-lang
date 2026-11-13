# Crafting an EYG interpreter

A compact implementation book for experienced programmers learning Zig.

This book accompanies `packages/zig_runtime`. The implementation is the example:
the [complete source appendix](source-listings.md) contains the files used to
build it, and `book_sources.py --check` detects drift. Read the prose in order,
then inspect the corresponding complete listings. Short examples in the prose
explain an idea; they do not substitute an unrelated toy evaluator for the real
program.

The target is the EYG implementation at `next-tui` commit
`be502aa03df926a8f9df474a0a7fe16c8fb14fbd`. Git behavior is informed by
`real-world` commit `f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9`. These are
independent inputs: adopting Git work does not silently move the TUI oracle.

An oracle makes compatibility measurable. It does not prove that the language is
correct, that every input has been tested, or that every device is fast enough.
The project's verification reports are evidence about the cases actually run.

## 1. Make the implementation reproducible

Begin with the package's build file and the pinned oracle, before changing any
semantics. Keep generated programs, event sequences, terminal dimensions, seeds,
and the oracle SHA in failure reports. A branch name alone is not reproducible.

Zig builds are programs. `@import("std")` imports the standard library;
`@import("parser.zig")` imports a module. `const` fixes a binding, while `var`
permits assignment. Source files are namespaces, so a small implementation can
keep clear module boundaries without an application framework.

This implementation targets **Zig 0.14.1**. With that version on `PATH`, build
and run the native package from `packages/zig_runtime`:

```sh
zig build -Doptimize=ReleaseFast
zig build test
./zig-out/bin/eyg eval -c '!int_add(20, 22)'
./zig-out/bin/eyg
```

The last command enters the interactive TUI. `--protocol` selects the JSON-lines
interface used by the differential harness; it is a test transport, not the
interactive UI. Protocol operations cover evaluation, parsing, TUI traces,
benchmarking, and Git queries.

Zig analyzes declarations lazily. Passing imported-module unit tests does not
establish that every CLI handler compiled. A thread-CPU clock change initially
passed those tests but used the wrong standard-library call signature in the
unvisited benchmark handler. Build the executable and smoke-test each changed
protocol operation before freezing source.

The source appendix is generated from canonical files. From this package:

```sh
python3 docs/book_sources.py
python3 docs/book_sources.py --check
python3 docs/book_sources.py --extract ../../work/book-example
cd ../../work/book-example
cd packages/zig_runtime
zig build -Doptimize=ReleaseFast
zig build test
```

The extractor verifies every file's SHA-256 before writing it. It refuses to
overwrite a different file. Build the reconstructed directory using the same
commands as this package; this is the check that the book contains the real
implementation's build inputs. The export includes the upstream evaluation
fixtures used by unit tests. Differential checks additionally need the pinned
upstream checkout and its compiled Gleam dependencies.

The [reconstruction proof](book-validation.json) records a build starting with
empty compiler caches, passing native tests, and the CLI result `42`. Its
ReleaseFast executable is byte-identical to the retained final desktop binary.
Android source reconstruction and Android execution remain separate checks.

The source reading order is `build.zig`, `src/parser.zig`,
`src/interpreter.zig`, `src/unicode.zig`, `src/ir_codec.zig`,
`src/computer.zig`, `src/http.zig`, `src/hub.zig`, `src/platform.zig`,
`src/effect_cast.zig`, `src/inspection.zig`, `src/source.zig`,
`src/capture.zig`, `src/inference.zig`, `src/pretty.zig`, `src/tui.zig`,
`src/oracle_order.zig`, `src/resume_inspect.zig`,
`src/async_git.zig`, `src/async_hub.zig`,
`src/input.zig`, `src/main.zig`, `src/git.zig`, `src/git_write.zig`,
`src/json_wire.zig`,
`src/git_config.zig`, then `src/android_bridge.zig`
and `android/`. `src/tests.zig` collects native unit tests. The appendix keeps
these file names so the examples can be reconstructed without editing imports.

**Library review.** Use Zig's build library for compilation and test steps. Use
Python's standard `hashlib`, `json`, and `pathlib` for the publishing utility;
adding a Zig dependency to a documentation extractor would not improve the
runtime. Pin the Zig toolchain because its standard library API changes between
releases.

**Code review.** Keep source listings generated. A manually copied second
implementation would create two things to debug and could teach code that no
longer passes the oracle.

## 2. Choose ownership before representations

Zig has no tracing garbage collector. A slice, `[]const u8`, carries a pointer
and a length; it does not own the bytes. A returned slice into a temporary
buffer becomes invalid when that buffer is released. Make this rule explicit
at the parser and interpreter boundary.

An allocator is passed as a value. The parser accepts `std.mem.Allocator` and
allocates its tokens and IR through it. A caller can use an arena for a complete
request and release all request storage together:

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();
```

`*T` denotes a pointer and `*const T` restricts mutation through that pointer.
`?T` adds a null case: `if (optional) |value|` unwraps a present value. These
forms describe the linked environments and optional host callbacks in the real
source; none extends the pointed-to allocation's lifetime.

`defer` runs at scope exit, including error exits. It is the normal way to keep
resource release beside acquisition. `error.OutOfMemory` belongs to the host
implementation; an EYG language break belongs to the interpreted program. Keep
those channels distinct.

An actual porting bug made this rule visible. AST labels borrowed the terminal's
reusable input buffer. Running `!int_add(20, 22)` and then typing `hello λé`
changed historical code to `!ello λ(20, 22)`. A real PTY comparison caught it.
The shell now copies input bytes into storage that outlives the parsed nodes.
Later, cached analysis storage invalidated earlier serialized frame symbols;
`Buffer.json` now copies symbols into the snapshot's owning allocator. A cache
can contain correct data while a borrowed result still has the wrong lifetime.

Discarded output needs a shorter owner too. Keeping JSON frames in the session
arena retained every temporary render even when the benchmark discarded its
answer. `Tui.frameAlloc(output_allocator, width, height)` now builds layout in
temporary scratch and copies its snapshot into the caller's output allocator.
The retained-trace `frame` convenience method deliberately uses session storage;
discarded frames use a reusable output arena. Ownership tests retain one frame,
reset other output arenas, edit the document, and check that the retained frame
and session capacity remain stable.

**Library review.** `std.heap.ArenaAllocator`, `std.ArrayList`, and
`std.json.Value` cover the current request representation. Reuse them before
inventing a collector, vector, or JSON tree.

**Code review.** An arena is simple, but a permanent TUI arena can grow on every
edit. A value retained after a request must retain its owner or be copied into
longer lived storage. Measure long sessions separately from single requests.

## 3. Parse into the stable IR

Read `src/parser.zig`. Its public `parse` function produces the canonical
DAG-JSON form used by EYG's IR. Surface syntax is convenient for people; the IR
is the differential test boundary. For example, application becomes an `a`
node, a lambda becomes an `f` node, and a let binding becomes an `l` node.

The lexer consumes a byte slice. The parser walks a token slice with a cursor;
`peek`, `take`, `accept`, and `expect` make grammar transitions visible. Recursive
descent is sufficient for this small grammar. It also makes the difference
between syntax errors and evaluation failures explicit.

EYG calls are curried. `f(x, y)` becomes application of `f` to `x`, followed by
application of the result to `y`. Lists and records are lowered to their IR
constructors. Record destructuring introduces bindings; it must not discard or
reorder evaluation.

In Zig, `ParseError!J` is an error union: either a JSON value or one of the
declared host errors. `try` unwraps success and returns an error from the current
function on failure. `catch` handles an error at the place it becomes meaningful.
These are explicit control flow, not exceptions.

**Library review.** Use `std.ascii` for the grammar's ASCII token classes,
`std.fmt.parseInt` for integer conversion, and `std.json.ObjectMap` for IR
objects. A parser combinator library would add an abstraction without removing
the need to match EYG's exact grammar. The custom code is the grammar, not a
replacement for general byte or collection operations.

**Code review.** Test successful and rejected syntax against the oracle. A
parser that accepts a plausible superset can still be incompatible. Preserve
the oracle's integer range and spread restrictions. Report missing syntax as
missing syntax, rather than accepting it with invented meaning.

## 4. Evaluate functions, data, and failures

Read the interpreter's value and evaluation definitions together. A tagged
union represents mutually exclusive runtime values. Zig's `union(enum)` pairs
the storage with its active tag; a `switch` can handle each case explicitly.
Avoid making every value an unchecked pointer and recovering its meaning later.
An arm such as `.integer => |number|` captures that case's payload. Zig checks
exhaustive switches, so adding a value kind identifies dependent printers and
converters at compilation. Functions taking `anytype` specialize for their
argument type; the writers use this to share formatting across output buffers.

A closure retains its parameter, body, and lexical environment. Applying it
extends that environment before evaluating the body. A builtin may return a
partial application until it has enough arguments. A record lookup, match, or
application that fails must produce the same EYG break as the Gleam oracle,
including the offending value where the language exposes it.

The production evaluator uses an explicit machine. `Control` selects expression
evaluation or a returned value. `Kont` records the next action and its lexical
environment. The `run` loop either evaluates the current expression or pops a
continuation, then repeats. A language tail call replaces control instead of
recursively calling Zig. Immutable environment links make closures inexpensive
to capture; immutable continuation prefixes make repeated resumption possible.

The transport representation is deliberately separate from the evaluator.
Tests serialize integers, strings, records, linked lists, binaries, tags, and
function markers. A function marker can establish that a result is callable;
it cannot establish two closures are extensionally equal. Generate applications
of functions to test their behavior.

Ordinary integers retain an `i64` fast path. The JSON host effect can expose
JavaScript integer values outside that range, including infinity after long
digit accumulation, so `Value.javascript_integer` preserves those IEEE-754
values. A shared number constructor chooses the representation. Checked
arithmetic still enforces the oracle's safe-result rules; divide, absolute
value, comparison, equality, byte conversion, and display follow its observed
behavior. Adding the union case made Zig identify the printers, capture code,
and type inference switches that also needed updating.

NaN reveals an additional representation rule. The oracle compares a boxed
value's identity before its payload: a bound NaN equals itself, while two fresh
NaNs differ. A quiet-NaN payload token preserves that identity across copied
native values. Generated programs test both cases and lists containing the
same bound NaN; comparing only serialized `null` would miss the distinction.

**Library review.** Use standard maps, lists, hashing, and JSON transport. The
evaluation rules remain EYG code: a generic expression library cannot decide
EYG's scoping, error, or partial-application semantics.

**Code review.** Prefer one implementation of each application rule. Keep
builtin dispatch readable enough to compare with the oracle. Check integer
overflow deliberately; Zig's machine integer behavior is not automatically
JavaScript's safe-integer behavior.

## 5. Suspend and resume effects

EYG programs interact with their host through effects. An interpreter must be
able to stop with the effect label and payload, retain the continuation, and
resume with a host reply. A test can provide a deterministic list of replies
without accessing a real filesystem, network, or phone.

This separation is useful beyond testing. The desktop runtime and Android host
can interpret the same program while providing different capabilities. New
effects should describe a reusable capability and have an explicit result
shape. Do not hide host errors or permission denials as successful values.

`src/effect_cast.zig` centralizes the computer effect payload checks shared by
desktop and sandbox hosts. Compare these casts against the actual Gleam cast
before running a host operation: malformed input should produce its language
break without performing part of the operation. Native-only effect extensions
remain separate from the pinned oracle's supported labels.

`src/computer.zig` implements `EYGParse`, `DecodeJSON`, `CreateKey`, and `Sign`.
`EYGParse` returns a pre-order list of tagged AST constructors. `DecodeJSON`
returns a pre-order stream of terms and nesting depths, preserving a number's
sign, integer part, decimal numerator/size, and exponent. A generic JSON object
tree would lose duplicate field order and lexical distinctions. Its explicit
scanner preserves the pinned Julienne parser's behavior, including accepted
trailing commas and ignored trailing top-level input.

Number accumulators follow the oracle's sequential IEEE-754 operations rather
than replacing them with an arbitrary-precision integer or one-shot float
parse. An unsafe value may have different exact binary bits and shortest
decimal text. The actual oracle comparison caught
`165057209463753869` becoming `165057209463753860` on output, while the first
native serializer printed its underlying integer bits as
`165057209463753856`. Shared ECMAScript number formatting fixes the wire and
printed forms. Infinite values serialize as JSON null while their display
remains `Infinity`; generated operation programs check the behavior after
decoding, including NaN, rather than comparing strings alone.

Ed25519 key generation and deterministic signing use
`std.crypto.sign.Ed25519`. Keys use the existing `Eddsa({kty, crv, x, d})`
contract, with a 32-byte public key and private seed. Signing ignores metadata
the oracle ignores, and checks the same private seed length. No OpenSSL is
needed for these operations. The pure-effect property checker invokes actual
Gleam handlers, compares signatures, and imports each generated native private
seed into the oracle to verify its public key:

```sh
zig test src/computer.zig
mkdir -p work
zig build-exe --dep computer -Mroot=tests/computer_runner.zig \
  -Mcomputer=src/computer.zig -femit-bin=work/computer-check
python3 tests/differential_computer.py --bun bun --cases 1000
```

`src/http.zig` implements `Fetch` and a shared read-only `get` transport with
`std.http.Client`, `std.Uri`, native TLS, and the standard certificate bundle.
It honors configured proxies, exclusions, and CA files. Responses retain binary
bodies and ordered headers. The local verifier compares actual Gleam transport
results, including redirects, compression, authentication removal, and tested
network failure strings. A refused CONNECT returns the proxy's HTTP response
without retrying directly. Invalid headers and out-of-range ports can throw
JavaScript constructor exceptions outside the oracle's Result contract; native
Fetch returns Error. These gaps remain listed in `http/README.md` and prevent a
complete HTTP parity claim.

**Library review.** Zig provides memory and serialization machinery; platform
libraries provide the actual capability. An effect protocol connects them.
Reuse the platform implementation of cryptography, compression, or phone APIs
where it meets the semantics and deployment constraints.

**Code review.** Continuation state must outlive the host operation. Exercise a
handler that resumes after additional computation, multiple successive effects,
and an unhandled effect. An interface that merely names an effect is not a
working host implementation.

## 6. Model the TUI as a state machine

The oracle already exposes the useful decomposition: `state.init`,
`state.update`, and `view.render`. A generated behavior trace starts with a
state, applies a key, paste, tick, or resize, drains the resulting host tasks,
and renders a buffer after each transition. This makes the first divergent
interaction visible.

The terminal shell has separate responsibilities: raw input, escape sequence
decoding, bracketed paste, resize handling, ANSI output, and restoring terminal
settings on exit. Test the reducer and the shell. A reducer can pass while the
interactive binary mishandles a split escape sequence.

The shell preserves incomplete UTF-8 scalars across reads before passing text
to the escape decoder. A `SIGWINCH` self-pipe wakes the poll loop for resizes;
the signal handler writes a notification instead of allocating or drawing.
PTY tests exercise both boundaries, including splitting a scalar's input bytes.

Buffer perfection includes each cell's symbol, display width, foreground,
background, modifiers, underline color, and link. Comparing only trimmed text
would discard exactly the information that distinguishes a correct terminal
clone from a visually similar one. Unicode continuation cells and clipping
deserve explicit cases.

Text order is another observable. JavaScript compares UTF-16 code units:
`λ`, `𐀀`, `😀`, `\u{e000}` have a different order from UTF-8 bytes. The shared
Unicode module compares those units without allocation for displayed records,
directory entries, and package choices. Canonical DAG-JSON and Git retain their
own byte-order contracts. One global "string sort" policy would be wrong.

The pinned completion code can use a UTF-8 byte count to slice a JavaScript
UTF-16 string, leaving an isolated surrogate. `src/json_wire.zig` preserves that
unit as a JSON escape through the standard writer's raw-string interface;
terminal output uses U+FFFD as JavaScript stdout does. This is a tested
completion edge, not a general contract for arbitrary invalid UTF-8.

`src/inference.zig` supplies level-based type inference with open record,
union, and effect rows. Type variables carry mutable links and levels;
generalization quantifies variables above the enclosing level, and
instantiation replaces quantified variables with fresh ones. Keep this mutable
type graph separate from immutable runtime values. Per-node analysis results
feed error styling, scope completion, and the status line.

The oracle profile keeps its closed effect declarations. Native hosts can enable
additional declarations for `GitQuery`, `Inflate`, and hashing. Heterogeneous Git
requests use `Dynamic`; the host validates each action rather than pretending
one fixed record type describes all requests. Test both profiles so an extension
does not silently change the oracle comparison.

`src/capture.zig` reconstructs IR from runtime values for scope inference. A
closure must capture only free names used by its body, selecting the newest
binding of each name. Walking every captured environment entry is both slower
and liable to get shadowing wrong. The scope cache can reuse the frozen type
context for an immutable runtime scope; clone mutable inference state for each
draft instead of allowing one edit's unification links to change another's.

An editable node does not always map to one lowered IR node. Synthetic
applications can share an annotation, and selection paths in the editable tree
differ from paths assigned during lowering. `Options.collect_paths` retains
preorder annotation occurrences; `Analysis.infoAtPath` selects the same first
occurrence as Gleam. A missing lookup produces no annotation. Reusing a node ID
or inventing a fallback type would display a plausible but incorrect status.

`src/pretty.zig` uses a small document algebra: text, sequence, line, nest, and
group. A group chooses a flat or broken layout according to available width.
This lets value and type printers share layout rules without making terminal
cell construction responsible for pretty printing.

Fixed builtin/effect type declarations are exported from the pinned source by
`scripts/export_types.mjs`; the native checker computes inference itself. Those
generated declarations and Unicode tables are fixed runtime data. The pinned
printer also exposes its builtin dictionary inside resumption inspection;
`scripts/generate_inspector.mjs` exports that fixed table. Native
`resume_inspect.zig` reconstructs the changing continuation, values, and
environments, while `oracle_order.zig` reproduces observable dictionary traversal
order. These tables contain no generated program results or terminal frames.
Keep generation scripts beside their checked-in outputs.
Inspection metadata also has a lifetime: closures, evaluator state, and
continuation frames retain the source location exposed by the pinned printer.
The runtime keeps that metadata separate from the control needed to execute.
`src/inspection.zig` shares each origin and source text; optional `_span` offsets
annotate located parser nodes. `src/source.zig` selects JSON or surface parsing
for disk imports, while content modules retain their CID origin. Differential
tests compare located trees and printed resumptions against actual Gleam;
canonical parsing and content hashing omit these inspection-only annotations.

`src/hub.zig` implements the read-only package ledger and module cache. Latest,
versioned, pinned, and content references have different lookup rules. Decode a
module into known IR fields, re-encode canonical DAG-JSON, hash with SHA-256,
then verify its CIDv1 identifier with codec 297. Hashing the original JSON text
would reject equivalent field order; hashing metadata would accept the wrong
contract. JavaScript's number layout also matters: `1e18` and
`1000000000000000000` have different hashes even when they represent one value.
The encoder reuses Zig's Ryu digits with ECMAScript's JSON layout rules.

Immutable modules initialize without host effects. The cache retains a broken
module's internal reason for diagnostics, while its caller receives an
unresolved-reference break. The actual Gleam cache comparison caught an initial
implementation that incorrectly propagated the module's inner failure.

The live shell begins with a ready package cache; many reducer tests begin with
an empty, already-pulled cache. Those profiles expose different behavior. Tests
now include seeded verified packages and a local HTTP hub serving real schema
entries and delayed modules. Settled-frame comparisons drain tasks first; they
do not establish equality of every transient loading frame.

`src/async_hub.zig` copies cache state into an independent worker arena and
merges a completed snapshot back on the UI thread. The worker and owner each
hold a reference; the last atomic release frees storage. Detaching a cancelled
network worker therefore leaves it no pointer into the departed UI, and network
I/O does not hold terminal cleanup. Git workers use the same two-owner lifetime
and detach on cancellation or shutdown.

```sh
zig test src/hub.zig
zig build-exe --dep hub -Mroot=tests/hub_runner.zig \
  -Mhub=src/hub.zig -femit-bin=work/hub-check
python3 tests/differential_hub.py --bun bun --cases 200
python3 tests/pty_hub.py
```

**Library review.** Standard collections and byte I/O are appropriate. Terminal
libraries may supply platform handling and Unicode widths, but adopting one is
useful only if its buffers can preserve the oracle's cell semantics. Keep the
oracle renderer independent from the Zig renderer.

**Code review.** Do not build compatibility by looking up recorded oracle frames
at runtime. Fixtures are evidence; the implementation must calculate the next
state and render it. Separate unsupported events from passing comparisons so
the denominator remains visible.

## 7. Generate comparisons that can fail usefully

Read `tests/oracle.mjs` and the differential harness. The adapter loads the
pinned compiled Gleam modules. It translates transport data and serializes
results, while evaluation and rendering remain the oracle's work. An adapter
that reimplements semantics would give both sides the same possible mistake.

From the original repository checkout, the complete entrypoint prepares pinned
dependencies, builds immutable test binaries, runs subsystem comparisons, then
measures performance after compilation:

```sh
./scripts/verify --setup
```

It writes `reports/verification.json` and a per-run directory of logs, hashes,
and detailed reports. `--quick` selects a diagnostic campaign;
`--skip-performance` omits timing. Neither supplies a full passing gate.
`--binary PATH` tests a retained copy of a particular executable. Known oracle
timeouts/crashes and unsupported HTTP behavior retain a strict red qualification.
The report, rather than completion of the command, determines the result.

Individual loops remain useful while repairing a failure:

```sh
python3 scripts/prepare_oracle.py
python3 tests/differential.py --bun bun --programs 1000 --syntax 200 --traces 100
python3 tests/differential_input.py --bun bun --cases 1000
python3 -m pip install -r tests/requirements.txt
python3 tests/pty_parity.py --gleam gleam
```

The default seed is recorded in each report. A saved failure can be rerun with
`python3 tests/differential.py --bun bun --replay reports/failures/CASE.json`.
Reports include the tested binary's hash, the oracle pin, counts, and differences;
use the report produced by the final binary rather than an earlier passing run.

Generate IR programs recursively with a bounded depth and an environment of
bound names. Mix valid terms with deliberate language failures. Include
functions, partial application, data constructors, handlers, Unicode strings,
integer boundaries, and nested structures. For effectful tests, compare the
requested label and payload before providing the reply.

Generate behavior as sequences, including meaningful actions in each TUI mode.
Always retain the full trace. When reducing a failure, first remove chunks of
events, then simplify individual events and programs while requiring that the
same comparison still fails. A seed alone is inadequate if the generator or
oracle has changed.

The current harness implements chunk removal for traces and greedy IR
subtree/constant shrinking for programs. It saves both the original and reduced
request. It does not yet shrink characters inside a paste event; that is a
useful extension when a single large paste is the smallest remaining trace.

**Library review.** Python and Node standard libraries provide reproducible
randomness, subprocess transport, and JSON comparison for this harness. A
property testing library is useful when its shrinking preserves validity and
the failure is replayable; it does not replace a recorded seed and trace.

**Code review.** Time out nonterminating generated programs. Distinguish decode
errors, language breaks, process crashes, and adapter failures. A successful
subset must not turn unsupported programs into test skips without a reported
coverage limit.

The pinned oracle supplies a concrete limit: paste `let x=1 x`, then press
Space. Its `morph.next_vacant` walk cycles without returning to the root
sentinel, so the request times out. Native Zig remains responsive. The timeout
and trace are retained, finite frame comparisons are reported separately, and
the strict parity gate remains false. An executable oracle can expose an
incompatibility without providing a usable answer for that input.

## 8. Measure the interaction the user experiences

The target is under 10 ms for a key interaction. Name the interval: input
received to state update, render complete, bytes written, or display observed.
These are different measurements. Use a monotonic clock, a release build, warm
and cold samples, realistic terminal sizes, and a history large enough to expose
work that grows with the session.

Report sample count, median, high percentiles, and maximum. Report allocation
and memory growth where possible. A passing median does not establish that
every interaction meets the target. A sub-millisecond no-op key says little
about import, evaluation, or Git history queries.

The checked-in native benchmark wraps dispatch plus complete cell-frame
construction with `std.time.Timer`. Run this after a complete parity run:

```sh
python3 tests/benchmark.py --bun bun --oracle
```

The combined result requires a passing
parity report as well as a passing latency gate; timing alone cannot certify a
clone. JSON serialization, terminal transport, and startup are excluded and are
identified as such in the report.
The full `scripts/verify` entrypoint runs this stage last to keep helper
compilation out of the measured interval.
Native samples run as one phase; that process closes before the oracle starts
and handshakes. Oracle startup or garbage collection must not compete with the
native phase and masquerade as interaction cost. Preserve every raw sample.
The timed interval includes resetting the reusable frame-output arena. The
memory-retention fix changes allocation lifetime, not which samples count;
earlier outlier reports remain available as a baseline.
Each sample retains monotonic wall time and the calling thread's CPU time from
`CLOCK_THREAD_CPUTIME_ID`. Only wall time gates 10 ms. Their difference helps
inspect waiting or scheduling delays; CPU timing neither proves their cause nor
replaces a slow wall sample with a passing result.

The retained `c1d288…a0edd` ReleaseFast campaign on Linux x86-64 produced the
following [recorded evidence](benchmark-evidence.json). Every one of the 12,800
native wall samples passed; no samples were filtered. These are measurements of
these workloads, not a bound on every future program.

| Interval | Samples | p50 ms | p95 ms | p99 ms | Maximum ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dispatch, frame, output reset | 12,800 | 0.356304 | 1.008371 | 2.464721 | 8.833814 |
| PTY key through complete frame | 16 | 0.497324 | 4.949743 | 4.949743 | 4.949743 |
| Live-hub PTY key through frame | 7 | 0.761952 | 1.741612 | 1.741612 | 1.741612 |

The PTY campaigns also passed 21 and 10 state/cleanup checks respectively.
The performance gate passed; the combined compatibility gate remained false
because of the documented oracle hangs/crashes and HTTP constructor gaps.

Review the observer too. An early PTY timer fed each incoming chunk through the
VT decoder before reading the next chunk, so its purported pre-decode time
included observer work. Accumulate bytes through the complete-frame marker,
timestamp receipt, then decode for comparison. Startup also needs matched hub
origins and drained old frames. Correct the driver and remeasure before treating
an apparent mismatch or delay as a runtime defect.

The oracle waits 40 ms before flushing an ambiguous incomplete terminal escape
sequence, and the native shell preserves that policy. An isolated Escape key
can therefore wait longer than 10 ms before dispatch even when rendering is
fast. A universal input-to-display claim needs to address this policy explicitly.

**Library review.** Use `std.time` for native timing and existing harness timing
facilities for subprocess measurements. Use a profiler before changing value
representations or adding caches.

**Code review.** Keep oracle process startup outside a hot-loop benchmark, then
measure startup separately. Do not remove rendering from a measurement called
key-to-frame latency. Optimization must rerun the same differential comparisons.

## 9. Read Git data without a command subprocess

The `real-world` branch supplies EYG Git behavior to study. Separate mutable
references from immutable content-addressed objects. Object and parsed-commit
caches can be retained; `HEAD`, branch refs, and packed refs need freshness rules.
A fast stale answer is incorrect.

Native object access must handle the repository forms it claims to support:
loose objects, packed objects, delta resolution, refs, and worktrees are distinct
features. Validate object identities and malformed input. Compare query results
with a trusted Git implementation and record which repository layouts are
covered.

`src/git.zig` implements SHA-1 loose objects, v2 indexes, packed objects with
OFS/REF deltas, worktree common directories, and first-parent history filters.
Use its `query` action with `contains`, `author`, `path`, `since`, `until`, and
bounded `limit`/`scan_limit` fields. `GitQuery` in `src/platform.zig` makes this
available to EYG. The independent `git/verify_native.py` compares real object
results with the Git executable; the executable is the verifier, not production
object plumbing.

`src/git_write.zig` adds local repository initialization, blob/tree/commit
creation, snapshots, and cooperative atomic reference updates.
`src/git_config.zig` manages local remotes. The `git/native.eyg` facade unwraps
`GitQuery`; binary object data crosses this effect as explicit base64 strings
with an encoding field, which is a native extension rather than the
`real-world` module's identical binary API. Native verification includes Git's
own object and repository checks. Writes need their own durability and race
tests, and their latency is not a key-render benchmark.

`src/async_git.zig` moves interactive Git effects to a worker with its own arena.
An acquire/release completion flag transfers the result; the UI copies it into
session storage before destroying the worker, then resumes the continuation on
the UI thread. The initial key can acknowledge work while the query continues.
Measure key response and query completion separately. Cancellation retires a
worker result; it does not preempt all underlying Git computation, and shutdown
releases its worker ownership without waiting for unfinished filesystem I/O.

The retained 20-record Git query campaign measured 100 native JSONL round trips
with a 2.782 ms median and 139.364 ms maximum, including repository/index setup,
inflate, hash checks, and structured records. OS caches were warm; each decoded
object cache began empty. Three Gleam samples per mode had cold/warm query
medians of 899/22 ms. Preserve the small comparator sample count and native
outlier. In the recorded interactive workflows, initial feedback took
0.80–3.64 ms while completion took 9.38–26.15 ms: those are separate results.

One useful code review changed the EYG facade's shape. Sequential `let`
definitions made each exported closure retain all preceding definitions.
Returning a record of lambdas sharing one `unwrap` binding reduced the captured
graph. The checker also filters unused captured names, addressing the general
case rather than relying on a specially shaped facade.

**Library review.** Use Zig standard hashing and compression where supported by
the selected toolchain. A mature Git library may be preferable when full Git
format coverage is required. OpenSSL is justified by a concrete cryptographic
or transport requirement, not by the fact that Git is involved. Adding it is
not itself a performance result.

**Code review.** Bound decompression and delta recursion. Keep the effect API
general enough to serve ordinary EYG programs. Report native extensions as
extensions when the pinned oracle does not provide them.

## 10. Give Android the same evaluator

Read `android/` alongside the native ABI. The native evaluator must have a small,
explicit ownership contract: how requests enter, how results leave, who frees
them, and how effect continuations are represented. Do not pass Zig's internal
struct layout directly to Kotlin or JavaScript.

The checked-in application uses a session-based C ABI: create, evaluate,
resume, result length, and destroy. `src/android_bridge.zig` holds an arena until
an effect reply resumes it. Kotlin copies result bytes while holding a lock;
JavaScript maps the effect to an injected host.

Zig's `export fn` supplies stable C symbols. `?*Session` is a nullable pointer;
`[*]const u8` is a byte pointer whose length is provided separately. This keeps
the boundary independent of Zig slice layout and JVM string representation.
`std.heap.c_allocator` supplies session storage and requires linking libc. The
bridge owns its result buffer; callers must copy before another operation or
destruction invalidates it.

The Kotlin module runs evaluation on an IO dispatcher. Its lock prevents a
session from being resumed and destroyed concurrently. The JavaScript session
loop uses `finally` to release the host and native session on success,
cancellation, and failure. This is the same ownership discipline as `defer`,
expressed at the language boundary.

The Kotlin session owner counts in-flight calls separately from public
ownership. Closing the app removes ownership immediately; the last IO worker
destroys native storage after returning. A short ownership lock and per-session
evaluation lock protect different invariants, so a slow verified network read
does not hold the UI's cleanup path.

Imports add another ownership boundary. A session retains parent evaluator
pointers while nested modules initialize, then restores the caller. Initialization
is pure; returned functions retain their source origin and can perform effects
when the caller invokes them. Native paths use `std.Uri` to decode `file://`
URIs, including percent-encoded spaces. The shared
native Git, hub cache, and Fetch handlers serve the Android bridge as well.
Android trust loading accepts PEM/DER certificates from the platform Conscrypt
and system CA directories; host-side TLS tests do not prove device execution.

**Library review.** Reuse the evaluator, standard allocator/JSON code, JNI, and
Expo's Kotlin module infrastructure. Keep native types behind the C ABI.

**Code review.** Validate request and reply types before accessing union fields;
keep the suspended arena alive; test repeated evaluation, invalid resume, and
destroy. A continuation is a live resource, not a serialized function marker.

## 11. Turn phone capabilities into effects

Expo supplies device integrations, permissions, lifecycle behavior, and UI
components. Those are libraries to reuse. A bridge exposes calls and event
subscriptions as effects; capabilities that require a mounted view need a UI
integration as well. Background work, camera previews, sensors, and a one-shot
clipboard operation have different lifecycles.

The injected `ExpoEffects` registry supplies five operations. `Expo` calls
methods, `ExpoNextEvent` receives queued callbacks, `ExpoRelease` disposes
resources, `ExpoView` mounts components, and `ExpoReply` answers asynchronous
SDK callbacks. A view ref can become a resource
handle for imperative methods. Module/member discovery helps explore APIs,
while an inventory records Android-capable registered modules.
View descriptors accept recursive children; refs are opt-in because many
functional components cannot accept one. The pinned SDK inventory classifies
registered entrypoints and explicit platform, legacy, development, or internal
exclusions, with no unclassified package hidden behind a capability count.

Some SDK operations await a callback result. Mark a call as deferred to receive
its operation handle, consume the callback event, answer its token with
`ExpoReply`, then await the operation handle. This keeps the interpreter able to
make the callback decision. Predetermined synchronous callback replies use
`expo_return`. An `expo_sync` source string makes an argument-dependent decision
in an isolated native VM, receiving the callback's argument list. It captures
no live continuation and accepts data arguments, with no effects or references.
A default 1,000-step
budget, maximum 10,000, covers definition and application; a standard fixed
allocator caps memory at 4 MiB. Source/request/output limits also apply.
Structural equality and substring split/replace builtins are rejected because
their work escapes the VM step counter. This bounded subset is not an arbitrary
EYG wall-time guarantee; failures throw back to the SDK callback. Canonical
DAG-JSON source can select camelCase/reserved SDK fields unavailable in surface
syntax. Date values retain a typed `expo_date` wrapper rather than silently
becoming strings.

The `eyg-background` adapter persists entrypoint source and metadata in
AsyncStorage. Sixteen TaskManager dispatchers are defined at bundle startup;
incoming events wait for restoration, then start a fresh native session with
`input = {data, error, execution_info, metadata}`. `define` returns a `task_name`
that must be registered through the ordinary Expo scheduling API. Defining
source grants no permission and schedules no OS work. `list`, `get`, `result`,
`run`, `cancel`, and `forget` manage definitions and invocations. Forgotten slot
identities stay reserved against stale deliveries; reclaiming the 16 historical
names requires verified OS unregistration and a JavaScript-process restart.

Widgets and custom notifications need a compiled layout callback. The
`eyg-widgets` adapter supplies a precompiled layout that accepts declarative
Text/Column/Row and other component trees. Its compiler is tested; posting and
home-screen rendering require device validation. New providers or native
layouts require a rebuild, and widget callbacks cannot capture a live EYG
continuation. See the Android README for the exact descriptor protocol.

The application's initial example runs through the native evaluator:

```eyg
let result = perform Expo({
  module: "expo-battery",
  method: "getBatteryLevelAsync",
  args: []
})
result
```

The host resumes with `Ok(value)` or `Error(reason)`. Permission-requiring APIs
still require their explicit Expo permission call. Native object results become
`{expo_handle: 1}` records; use a matching callback record such as
`{expo_callback: "motion"}` when registering an event producer.

EYG source literals use safe integers, while phone APIs often use fractional values. The bridge
therefore preserves an explicit `{expo_number: "0.74"}` wrapper for fractional
Expo numbers and `{expo_bytes: [0, 255]}` for byte arrays. These are host data conventions,
not new EYG numeric syntax. Capability listings must state that distinction.

Bridge records must also be expressible in EYG source. Use `expo_handle` rather
than the reserved `handle`, and `timeout_ms` rather than a camelCase field.
For SDK dictionaries with foreign names, construct
`{expo_object: [{key: "shouldShowBanner", value: True({})}]}`. Read a foreign
property through `Expo({object: data, method: "canAskAgain", get: True({})})`.
Testing JSON requests alone would miss these source-language restrictions.

**Library review.** Reuse Expo modules for phone APIs. Reimplementing the
platform APIs in Zig would enlarge the permission, lifecycle, and compatibility
burden. EYG sees one general host protocol rather than a new language primitive
for every SDK method.

**Code review.** Bound event queues, report dropped events, close subscriptions
on cancellation, and dispose late arriving resources. Reject invalid member
paths. Registry presence does not establish that every SDK method works through
every possible argument, callback, or UI lifecycle.

## 12. Repeat the verification loop on Android

Use the same generated-program oracle comparison through the C ABI. The native
bridge is an additional boundary, so compare its serialized values and breaks,
then separately test suspension/resumption. Inject fake phone modules for
repeatable callback, resource, rejection, and cancellation tests; do not require
GPS or a particular battery level to test the effect protocol.

The touch application is a source editor and result surface. Its UI is separate
from the terminal buffer renderer, so interpreter agreement does not establish
that Android interactions clone the TUI. Touch behavior and accessibility need
their own generated interaction and device tests.

From `android/`, with Node, JDK, the Android SDK/NDK and Zig 0.14.1 installed:

```sh
npm ci
npm test
npm run typecheck
npm run prebuild
npm run build:zig
cd android
./gradlew assembleDebug
```

Set `ANDROID_NDK_HOME` and `ZIG` for the native build. The build script creates
ARM64 and x86_64 shared libraries with an explicit API 26 libc/sysroot; SDK
installation and a device/emulator remain deployment prerequisites. Run
`npm run check:capabilities` from the app directory to inspect registered
Android-capable modules. That inventory is not a hardware test.
The text appendix excludes binary Gradle-wrapper and generated application
assets; `npm run prebuild` regenerates that scaffolding from the included Expo
configuration and locked dependencies.

Package installation, TypeScript checking, native cross-compilation, APK
assembly, emulator execution, and physical device verification establish
different facts. Record them separately. The host-built C ABI tests exercise
real Zig code but do not execute an Android binary. Device latency needs input,
native evaluation, bridge, and rendered-frame measurements on that device; a
desktop 10 ms benchmark cannot substitute for them.

The final host C ABI campaign ran 10,000 samples each for evaluation, effect
resumption, and isolated pure callbacks. Maxima were 1.451397, 0.602198, and
2.202104 ms; pure timing includes fresh-session creation and destruction. These
are host-native measurements, excluding phone rendering and SDK execution;
`android/native-benchmark.json` records the exact library/source hashes.

The recorded APK build is blocked by an HTTP 403 policy denial for the Maven
redirect to `repo.reactnative.dev`. The source, host tests, and native build
results remain reviewable; an APK, device launch, and hardware behavior must not
be inferred from those checks. `android/validation.json` and the app README
record the exact packaging and native-library status. Background continuation
persistence is distinct from durable entrypoints: source/options restore into
a fresh VM. Host tests exercise restoration across fresh native processes;
actual Android restart delivery, scheduling, and battery restrictions remain
device checks. A suspended continuation is not serialized across process death.

An isolated React Native source-build check also stopped before its task graph:
the Kotlin Gradle plugin was uncached, required upstream sources were absent,
and Boost's publisher was outside the enforced allowed hosts. The Android
`source-build-feasibility.json` records that investigation; it produced no APK.

**Library review.** Reuse the desktop generator and oracle, Node's test runner
for the injectable host, and Gradle/Expo for packaging. Retain package-lock
versions and explicit NDK/toolchain selectors.

**Code review.** Keep capability inventory, host protocol tests, C ABI parity,
APK assembly, and hardware checks as separate results. A usable app should
propagate failure and release resources even when the OS pauses its activity.

## 13. Treat the recording as a reproducible experiment

A useful demonstration records the command, terminal dimensions, repository
revision, query source, resulting frames, and timing metadata. Use actual EYG
Git history. Choose queries that combine traversal, filtering, and aggregation,
such as identifying concentrated changes by path or author over a bounded
history. Keep the underlying data and query available beside the recording.

**Library review.** Existing terminal recording formats and players are more
portable than a custom video container. A scripted replay can make the capture
repeatable, while the binary still computes every frame.

**Code review.** Label a synthetic fixture or scripted trace clearly. A renderer
replay is not evidence that the interactive process executed the queries.

## 14. Close the loop

For each change, regenerate programs and traces, save a small regression for
every discovered mismatch, rerun performance cases, and refresh the source
appendix. Review libraries again when the bottleneck or deployment target
changes. Replacing twenty clear lines with a large dependency is not
automatically cleaner; duplicating a correct standard library primitive is not
automatically faster.

Read [the library and code review](library-and-code-review.md) for concrete
implementation findings and [the talk](talk.md) for the narrative behind this
workflow. The book is finished only to the extent that its build, comparisons,
performance evidence, and Android verification are reproducible. Remaining
limits belong in the release report, not in a footnote hidden by a success claim.
