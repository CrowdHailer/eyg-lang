# Library and implementation review

This review accompanies [Crafting an EYG interpreter](book.md). The reference
toolchain is Zig 0.14.1. Library reuse includes Zig's standard library: a package
dependency is warranted when it supplies missing behavior and can preserve the
oracle contract. Small language-specific rules remain explicit.

## Chapter decisions

| Chapter | Library opportunity used | Implementation review |
| --- | --- | --- |
| 1. Reproduction | `std.Build`; Python `hashlib`, `json`, `pathlib` | One canonical source tree; generated, hashed appendix reconstructs a build tree. Pin both oracle SHAs. |
| 2. Ownership | `std.heap.ArenaAllocator`, `std.mem.Allocator`, `std.ArrayList` | Request arenas simplify cleanup; a session arena is not a bound on memory growth. Borrowed source bytes must outlive their IR. |
| 3. Parsing | `std.ascii`, `std.fmt.parseInt`, `std.json.ObjectMap` | Recursive descent keeps EYG grammar visible. Differential syntax checks are required; custom parsing is not permission to broaden the language. |
| 4. Evaluation | `std.StaticStringMap`, `std.meta`, `std.base64`, standard collections | Explicit continuation loop avoids evaluator recursion for language calls. Keep spec conversion separate from runtime values. |
| 5. Effects | Standard JSON/Unicode and callbacks; `std.crypto.sign.Ed25519`; `std.http.Client`, native TLS and certificate bundle | Effects can suspend/resume. JSON preserves lexical numbers/flat stream. Reply validation, verified transport and continuation lifetime are part of the API. |
| 6. TUI | Standard allocation, UTF-8 decoding, collections, I/O, SHA-256 and Ryu formatting | Native AST/reducer calculate frames; verified hub/cache has separate empty, fixture, and live profiles. Worker snapshots have explicit owners. |
| 7. Generated tests | Python `random`, `subprocess`, `select`; compiled Gleam libraries | Independent program generation avoids using Zig parsing as both generator and implementation. Shrink by rerunning both peers. |
| 8. Performance | `std.time.Timer`; Python monotonic timers and statistics | State update plus frame generation is a useful interval, but excludes terminal I/O and physical display latency. |
| 9. Git | `std.compress.zlib`, `std.crypto.hash.Sha1`, base64, filesystem | No production Git subprocess. Index binary search, immutable object cache, fresh refs, bounded inflate/deltas; separate local writes/config. No OpenSSL dependency is needed for these local SHA-1 operations. |
| 10. Android evaluator | Shared evaluator; standard JSON/C allocator; JNI and Expo Kotlin module bridge | C ABI owns sessions and result buffers; copy results under the session lock. |
| 11. Phone effects | Expo modules | Distinguish methods, resource handles, callbacks, and mounted UI; platform permissions remain Expo/Android behavior. |
| 12. Android verification | Shared program generator; Node test runner; Gradle/Expo | C ABI parity, host tests, APK builds and actual device behavior establish different facts. |
| 13. Recording | Terminal recording format and existing players | Keep actual query text and revision beside the capture. Playback is a demonstration artifact, not an independent parity test. |
| 14. Maintenance | Build/test tools and generated source checks | Regression fixtures complement generated coverage. Library or cache changes must rerun both parity and timing checks. |

## Runtime code review

`src/interpreter.zig` has an explicit `Control` state and a linked continuation
stack. Lexical environments and linked lists are immutable. A captured effect
continuation copies the prefix that must attach to a new caller, allowing a
resumption to be used more than once without mutating the original stack. These
choices make scope and handler behavior inspectable. The linked structures still
allocate; a tail-call-safe control loop does not imply constant memory usage.

The builtin table uses `std.StaticStringMap` generated from the builtin enum,
removing a second manually maintained dispatch list. Ordinary integer arithmetic
uses a wider intermediate before checking JavaScript's safe-integer range;
unsafe host values take the observed IEEE-754 path. JSON value
conversion and human inspection are separate operations. The spec suites test
the language representation; the differential harness supplies independent
generated terms.

`src/unicode.zig` uses `std.unicode` for decoding, with checked-in Unicode 16
property and case tables from `scripts/generate_unicode.py`. Development uses
`regex==2024.11.6` and ICU 76; the binary does not require Python or ICU. The
standard library's encoding support does not provide EYG's full grapheme and
case contract. Generated tables avoid a runtime dependency while preserving a
specific Unicode version. Regeneration must verify tool versions rather than
silently changing them.
The same module provides allocation-free UTF-16 comparison for the pinned
JavaScript target's public string ordering. Actual Gleam comparisons exposed
UTF-8 ordering in displayed records and pickers; canonical JSON and Git byte
ordering remain separate. No grapheme policy changed to fix comparison.

`src/json_wire.zig` reuses the standard JSON writer and escaping, handling only
the isolated UTF-16 units the pinned completion path can create. WTF-8 internal
units become JSON surrogate escapes; ANSI output replaces them like JavaScript
stdout. Focused cases exercise this transport boundary without claiming general
invalid-UTF-8 compatibility.

`src/parser.zig` lowers curried calls and record/list syntax into the oracle's
IR. It has deliberately small helper functions for constructing IR objects.
Error handling is explicit. Token offsets are recorded; richer diagnostics can
use them without changing the grammar. Shared value decoding now checks JSON
tags and safe-integer bounds before reading tagged-union fields, preserving the
same invariant for CLI and Android callers.

`src/inference.zig` replaces the initial string-only analysis with an independent
level-based Hindley–Milner checker, including open record, union, and effect
rows. Fixed declarations come from `src/builtin_types.json` and
`src/computer_types.json`, exported from the pinned source by
`scripts/export_types.mjs`; inference results are computed in Zig. `src/capture.zig`
reconstructs IR from runtime values, filtering closure free variables and
respecting lexical shadowing. A frozen scope context can be reused for an
immutable scope, with mutable inference state cloned for each draft. The separate
`src/pretty.zig` document algebra supplies value/type layout.
Native-only declarations are gated by `inference.Options.native_effects`; the
oracle profile stays closed. `GitQuery` uses `Dynamic` at heterogeneous request
and result boundaries, with runtime host validation. Tests cover different
action shapes and continued rejection of unknown effects.
`Options.collect_paths` retains annotated occurrences in actual preorder, and
`Analysis.infoAtPath` reproduces the oracle's first matching annotation.
Synthetic lowering can share IDs and use paths different from the editable
projection; missing annotations remain blank rather than borrowing a nearby
type. Tests distinguish the primitive and enclosing application occurrences.

`src/resume_inspect.zig` reconstructs the pinned generic inspector's observable
continuation text. Its changing frames, environment, and values come from the
native machine. The fixed builtin dictionary description is generated by
`scripts/generate_inspector.mjs`; `src/oracle_order.zig` models the dictionary
traversal order exposed in diagnostics. Standard maps remain appropriate where
their internal order is not part of an observable result. Closure, evaluator,
and continuation inspection metadata preserves source locations without making
printer metadata the evaluator's control representation. `src/inspection.zig`
shares origin/source data while located parser nodes carry byte offsets;
`src/source.zig` applies disk or content provenance without changing canonical
IR. Actual Gleam comparisons cover located syntax trees and resumption text.

`src/tui.zig` contains the native node tree, snapshots, reducer, IR conversion,
analysis integration, renderer, and terminal buffer. The buffer exposes all
cell properties needed for comparison; its ANSI encoder is separate.
Broad generated success is useful evidence, but cannot justify
an unrestricted claim of identical analysis or imports.

This module is large enough that future changes should preserve its internal
boundaries. Extracting the terminal buffer and Unicode width policy would make
the reducer easier to review without creating a generic UI framework. Keep
oracle differences visible before attempting structural refactors: a clean
abstraction that changes buffer output would fail the task.

`src/git.zig` handles loose objects and v2 pack indexes, including OFS and REF
deltas. It verifies requested object hashes and index checksums, supports
worktree common directories, and restricts history queries to first-parent
traversal. Decompression size and delta depth are bounded. It does not implement
all Git features, SHA-256 repositories, or a network transport. The object cache
budget bounds cached entries, not all allocations retained in the request arena.

Local write operations live separately in `src/git_write.zig`: initialize a
repository, write content-addressed objects, create snapshots, and update refs
cooperatively and atomically. `src/git_config.zig` isolates repository-local
remote configuration. Native verification uses Git for object comparison,
repository consistency, and write-race checks. Filesystem durability may require
latency above 10 ms; write timing must remain separate from the rendering gate.

`src/platform.zig` attaches filesystem, time, random, hashing, inflate, and Git
capabilities to the evaluator. New `GitQuery` is a native extension for querying
a repository; its request format is general enough for EYG modules to compose
history filters. `Inflate` is a reusable binary transform. `Hash` uses Zig's
standard implementation instead of introducing OpenSSL solely for hashing.
`src/effect_cast.zig` centralizes the pinned computer payload checks; handlers
apply it before performing host work. Its independent oracle comparison can
validate rejected requests without invoking their filesystem/network effects.

`src/computer.zig` supplies pure parsing, lexical JSON decoding, Ed25519 key
generation, and deterministic signing. Standard Unicode/crypto primitives are
reused. The JSON state machine is custom because the oracle returns a flat
lexical term stream with duplicate fields and permissive edge behavior, which
`std.json.Value` would not preserve. The checked-in property runner compares
actual Gleam handlers for valid and malformed cases. A separate IEEE-754 integer
variant supports values beyond `i64`, while ordinary source integers keep their
fast path. Shared ECMAScript text conversion handles unsafe values; JSON emits
null for non-finite results. Additional programs exercise arithmetic, division,
comparison, byte conversion, equality, and display after the actual decode.

`src/http.zig` reuses the standard HTTP client, URI parser, certificate bundle,
and native TLS. A review found the Zig 0.14 stock proxy helper did not perform
the required authenticated CONNECT/TLS upgrade, so those steps are explicit.
Per-request scratch is released, while response bodies/headers belong to the
caller. Local tests cover real transport and certificate failures. Known
constructor-exception differences, IP-only SAN certificates,
and nested TLS through an HTTPS proxy are documented in `http/README.md`.
Refused CONNECT responses, including 407, are returned without an origin
request or a direct/plaintext fallback.

`src/hub.zig` canonicalizes only known IR fields, normalizes binary/CID aliases,
sorts UTF-8 keys, and hashes canonical DAG-JSON with SHA-256 before accepting a
module. It reuses the standard Ryu conversion with ECMAScript JSON layout so
large integral version numbers produce the oracle's bytes. Modules initialize
without host effects; inner invalid-module reasons are retained for diagnostics,
while callers receive an unresolved-reference break. Ledger pulls are GET-only.
Unknown live names/versions refresh incrementally once; static fixture caches
disable refresh-on-miss.

`src/async_hub.zig` transfers deep snapshots into a worker arena and merges a
completed snapshot into UI-owned storage. Two reference owners and an atomic
last-release rule allow network workers to finish after terminal cleanup
without keeping pointers into UI memory. Git workers use the same ownership
rule for outstanding filesystem work.

`src/async_git.zig` owns requests/results in a worker arena, publishes completion
with an acquire/release atomic flag, and leaves continuation resumption on the
UI thread. Results are copied before releasing the UI's worker ownership. An
unfinished worker is detached; the last owner releases its arena. This
improves interaction responsiveness; it does not make query completion or
durable writes intrinsically shorter than 10 ms.

`src/android_bridge.zig` keeps JVM objects outside Zig and serializes access to
each session. A result pointer remains valid until the next session operation
or destruction; JNI must copy its bytes before releasing the lock. The JS host
is injectable, permitting effect tests without a phone. Registry presence does
not establish hardware support or correct behavior for every Expo method.
Nested view descriptors and opt-in refs reuse React/Expo components. The
precompiled `eyg-widgets` layout converts declarative trees for widget and
notification APIs; compiler checks do not establish device rendering. The
pinned SDK inventory records registered entrypoints and explicit exclusions.
Synchronous argument-dependent callbacks use an isolated VM and standard
`FixedBufferAllocator`, with explicit step/input/output limits. Pure-mode guards
reject effects, references, structural equality, and substring searches that
can do substantial work outside the VM loop. Binary argument expansion is
charged before conversion. Async callbacks keep the ordinary evaluator.
`eyg-background` reuses AsyncStorage and global TaskManager dispatchers to restore
entrypoint source into fresh sessions. Persistent slot identities prevent one
task name from inheriting another's deliveries; reset requires OS unregistration
and a JS restart. This stores definitions, not live continuations, and host
restart tests do not establish actual Android scheduling behavior.
Import initialization retains parent evaluator pointers and stays pure; returned
closures retain their source origin and can perform phone effects when called.
File URIs use standard percent decoding. Git, hub, and native Fetch are
shared with the Android bridge. Android TLS reads the platform trust directories;
APK assembly and actual device behavior remain separate verification gates.

## Findings sent back to implementation owners

These are concrete review findings, not a claim that every remaining path has
been exhaustively audited. Refresh their status with the final verification
report.

- **CLI effect replay:** serializing a failure by calling evaluation again could
  repeat earlier host effects. The entry point was changed to serialize the
  existing failure after one execution.
- **Borrowed terminal input:** labels retained bytes from a reusable input
  buffer, corrupting old ASTs when the next input arrived. Real PTY tests caught
  historical `!int_add` changing to `!ello λ`. Input now owns its retained bytes.
- **Cached frame snapshots:** cell symbols initially borrowed analysis storage
  that a later edit could invalidate. Snapshot serialization now copies each
  symbol into the caller's allocator. Repeated cells can share immutable,
  caller-owned maps without reviving that lifetime bug.
- **Short pack underflow:** checking `offset >= stat.size - 20` on a malformed
  pack shorter than its trailer could underflow. The Git owner was asked to
  guard minimum pack length before subtraction. The guard and malformed
  12-byte-pack test were implemented.
- **Frame annotation lifetime:** temporary rendering allocations stored as node
  type/problem slices can outlive their arena. The TUI owner was asked to make
  annotation lifetime explicit, including history nodes. The final path keeps
  analysis in its owning cache and removes unused Node annotation fields and
  their tree walks. Render scratch does not escape. `renderAnsiAlloc` gives the
  caller ownership of ANSI output; the shell releases it after writing.
- **Discarded JSON frames:** render and snapshot allocations used the permanent
  session arena even when callers discarded each frame. `frameAlloc` separates
  temporary layout from caller-owned output. Retained protocol traces still use
  `frame`; benchmarks reset a separate reusable output arena inside the timed
  interval. Ownership regressions preserve an earlier frame across resets and
  edits, and check session capacity across repeated renders. Previous outliers
  remain recorded; the implementation must earn any timing improvement.
- **Paired clocks:** raw monotonic wall and calling-thread CPU samples are
  retained together. Reports attach CPU time and the wall-minus-CPU difference
  to slow samples for diagnosis. Only wall time controls the 10 ms gate; the
  diagnostic never removes an outlier or substitutes for elapsed response time.
- **Lazy analysis preflight:** a wrong `clock_gettime` signature survived unit
  tests that did not instantiate the main protocol handler. The complete
  executable build and an actual `bench_tui` request are required preflight for
  that change; importing a source module does not compile all its declarations.
- **Unicode duplication:** the TUI's initial grapheme iterator duplicated a
  subset of the shared interpreter segmenter. Segmentation is now shared;
  display width follows the pinned ETUI first-codepoint policy separately.
- **Unicode sorting:** supplementary characters and BMP private-use labels
  distinguished JavaScript UTF-16 order from native UTF-8 order. A shared
  comparator now serves public record/picker ordering, with directed and random
  oracle cases. Directory names are compared before appending their display
  slash, matching the oracle's list-then-format pipeline.
- **Wire validation:** `Engine.fromJson` initially assumed matching JSON union
  tags. Validate malformed input at the shared conversion boundary so a bad
  effect reply cannot panic or enter undefined behavior in a release build.
  The shared conversion now validates tags and bounds, with rejection tests.
- **Unicode regeneration:** the generator initially described pinned library
  versions without checking them. It now asserts the expected regex and ICU
  versions before emitting tables.
- **Closure scope inference:** an initial direct walk reversed shadowed
  bindings and traversed unused captured values. Runtime-to-IR capture now
  filters free variables and selects the newest binding, matching the oracle's
  capture contract. The EYG Git facade also uses record lambdas sharing one
  binding instead of retaining a chain of preceding exported closures.
- **Type declaration generation:** the exporter now verifies the oracle HEAD
  and tracked cleanliness, handles URL-escaped paths correctly, and omits an
  unused generic serializer. It exports declarations, never cached inference
  results.
- **Canonical module bytes:** a direct JSON hash would retain ignored editor
  metadata and Zig's scientific number layout. Known-field normalization and
  ECMAScript number formatting now match the actual oracle's module bytes.
- **Escaped JavaScript integers:** JSON decoding exposed unsafe values whose
  shortest JavaScript decimal differed from the native serializer's exact i64
  text. Shared formatting fixed that case; an additional numeric variant and
  unsafe-operation tests cover values beyond i64 and non-finite results.
- **NaN identity:** the oracle recognizes the same boxed Integer object before
  checking its payload. Ordinary IEEE equality lost that observable behavior
  for a bound NaN. Quiet-NaN identity tokens now survive native value copies;
  generated programs distinguish bound values, copied list elements, and fresh
  NaNs instead of relying on their identical JSON `null` representation.
- **Broken module visibility:** a failed module initially leaked its inner
  break into its caller. Actual Gleam cache comparisons showed that callers see
  their unresolved reference instead; the inner reason now stays in the cache.
- **Cache refresh:** a drained live ledger initially prevented newly published
  names/versions from being discovered. A local transport regression now adds
  releases mid-session and verifies one incremental refresh per miss, without
  polling for known names or touching the network for static fixtures.
- **Oracle nontermination:** pasting `let x=1 x` then pressing Space makes the
  pinned `morph.next_vacant` walk cycle without returning to the root sentinel.
  Native navigation remains responsive. The retained timeout keeps strict
  parity false; finite comparisons are a separate result, not a replacement
  for this counterexample.
- **Test-driver boundaries:** the Git driver assumed every successful result
  was a JSON object, although history and identifier operations return lists or
  strings. PTY startup also needed matched origins and drained frames. A timer
  labelled pre-decode still decoded intermediate chunks; receipt must be timed
  through the complete-frame marker before VT observation. Driver failures
  require correction and remeasurement, not a runtime patch or a passing claim.
- **Android numeric results:** fractional Expo results need an explicit bridge
  representation because EYG source has safe integers, not floating-point literals.
  Returning a bare string loses the type needed to call a later numeric API.
  The host now preserves `{expo_number: "0.74"}` on encode/decode; its tests cover
  the typed round trip.
- **Android binary replies:** the initial Android reply validator omitted the
  existing binary value form. Binary validation was added to the native bridge.
- **Android source syntax:** JSON-only bridge tests accepted reserved or
  camelCase fields that EYG source cannot construct. The public examples now
  use `expo_handle`, `timeout_ms`, and explicit `expo_object` key/value entries;
  foreign properties are accessed through the bridge's `get` operation.
- **Bounded file reads:** allocating the entire requested read length retained
  128 MiB for a tiny file. The host now reads chunks and retains only actual
  bytes, preserving the requested limit without treating it as an allocation
  requirement.

Formatting with `zig fmt` improves readability, but is only the start of code
review. The useful follow-up is to run the extracted book example, unit tests,
differential comparisons, malformed-input checks, performance workloads, and
Android host tests against the final source. Their reports determine the
release claims.

`scripts/verify` orchestrates that campaign, retaining an immutable executable,
source/report hashes, and per-suite logs before running the performance stage
last. Quick or timing-omitted runs remain diagnostic. Known oracle failures and
unsupported behavior keep strict qualification false rather than disappearing
from the successful finite subset.

The final [book reconstruction proof](book-validation.json) records a clean-cache
ReleaseFast build, passing native tests, and CLI evaluation from the extracted
tree. Its executable matches the retained desktop binary byte for byte. This
verifies the native example's build inputs; it does not supply missing APK or
device validation.
The earlier [2cb198 baseline proof](book-validation-2cb198-baseline.json) is
preserved separately from the follow-up frame-allocation work.
