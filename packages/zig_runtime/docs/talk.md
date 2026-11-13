# Porting EYG with an executable oracle

A 60–75 minute technical talk with a live demonstration and discussion. The
[67-slide deck](https://chatgpt.com/space/page_38b0eecb8da081919a205d2a9b6931cf)
includes 44 controlled before-and-after comparisons and one historical campaign.
The opening walkthrough keeps its original pacing. The complete optimisation
section below supplies the detailed mechanisms and measurement limits. The accompanying
implementation and [book](book.md) target Zig 0.14.1. The oracle is the Gleam
`next-tui` branch pinned at
`be502aa03df926a8f9df474a0a7fe16c8fb14fbd`; Git work is compared with
`real-world` at `f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9`.

## 1. A compatibility claim needs an experiment — 2 minutes

Open with the familiar command:

```sh
cd packages/gleam_cli
gleam run -- tui
```

Then show the new executable:

```sh
cd packages/zig_runtime
./zig-out/bin/eyg
```

The intended user experience is the same. A screenshot can demonstrate a
pleasant first frame; it cannot establish compatible behavior. The useful
question is whether both implementations produce the same observable result
after the same inputs.

Explain three independent targets: language behavior, terminal buffers, and
latency. Passing one does not imply either of the others. We need separate
evidence for each.

## 2. Freeze the oracle — 2 minutes

Show the commit hash beside the branch name. A branch is a moving development
line; the hash identifies the experiment. Use a separate checkout for the
oracle, compile it, and leave its evaluator and renderer unchanged.

The thin Node adapter in `tests/oracle.mjs` loads compiled Gleam modules. It
decodes canonical EYG IR, invokes the existing interpreter, and serializes its
answer. For TUI tests it calls the existing state reducer and renderer. It must
not implement an alternative EYG interpreter inside the adapter.

Speaker note: explain that an oracle can contain bugs. This project deliberately
tests compatibility with this version. A correction to the language should be a
separate change to the oracle and compatibility contract.

## 3. Draw one test boundary for each observable — 3 minutes

```text
seed → generated program ─┬→ Zig evaluator ──→ result or language break
                         └→ Gleam evaluator → result or language break

seed → generated events ─┬→ Zig state/render ──→ frames
                         └→ Gleam state/render → frames
```

Values are compared structurally: integers, strings, binaries, lists, records,
tags, and a marker for functions. To test a function, apply it to generated
arguments. A function marker alone is a weak observation.

Terminal frames are compared as cells. Include symbol, display width,
foreground/background, modifier bits, underline color, and links. Unicode
continuation cells are part of the output. Trimming rows or stripping ANSI
would make the experiment unable to detect some rendering errors.

Show one cell difference with its event index and coordinates. It turns an
unhelpful “looks wrong” report into a specific transition to inspect.

## 4. Generate programs, including useful failures — 3 minutes

The generator produces bounded EYG IR rather than arbitrary text. Keep an
environment of names in scope and a depth budget. Generate literal leaves,
applications, closures, lets, records, tags, matches, and effects. Add deliberate
undefined names, wrong argument types, missing fields, and integer boundaries.
The expected answer comes from the oracle, not from an assertion that every
generated program succeeds.

For effects, supply a deterministic host script. Before resuming execution,
compare the effect label and payload, then provide the same reply to both
interpreters. A host that returns the right final answer after requesting the
wrong effect is still incompatible.

Speaker note: identify “code generation” precisely. The test harness generates
**programs under test**. Production control flow is ordinary Zig source.
Generated runtime data consists of Unicode property/case tables and fixed
builtin/effect type declarations, plus the fixed builtin dictionary text exposed
inside resumption inspection. It contains no answers for generated programs or
terminal frames. Unicode generation pins regex/ICU versions, and declarations
and inspector constants come from the pinned oracle. The native evaluator,
inference engine, and continuation inspector compute changing results themselves.

## 5. Generate user behavior — 3 minutes

A user trace contains keys, bracketed paste content, ticks, terminal resizes,
and deterministic file replies. Some actions are uniformly sampled to expose
unexpected mode combinations; others are structured workflows that reach
editing, execution, history, and import states.

Render the initial state and every subsequent state. Drain each transition's
tasks before comparing its final frame when that is the harness contract. Keep
asynchronous ordering as a separate test dimension if the production shell can
render intermediate states.

Save the seed, complete trace, terminal size, oracle SHA, and mismatch. Replay
the trace before debugging. Reduce traces by removing chunks of events and
reduce programs with greedy subtree/constant shrinking. A reduced
case becomes a permanent regression. The generated test remains useful because
its future seeds explore beyond that regression.

Show an oracle limit too: paste `let x=1 x`, then Space. The pinned vacant-node
walk cycles without returning to its root sentinel. Zig remains responsive,
but that is still a divergence: preserve the timeout and keep the strict parity
gate false. Passing finite comparisons and timing samples cannot erase a
nonterminating reference transition.

Speaker note: shrinking individual paste strings is useful future work. The
checked-in event shrinker removes complete events.

## 6. Port in Zig without inventing infrastructure — 3 minutes

Explain the small Zig vocabulary needed to read this code:

- `[]const u8` is a borrowed byte slice, not an owning string.
- An allocator gives explicit ownership and allocation failure.
- `defer` keeps cleanup next to acquisition.
- `ErrorSet!Value` is an error union; `try` and `catch` make its control flow
  visible.
- A tagged union plus `switch` models values and continuations directly.

Use the standard library for JSON, collections, integer parsing, allocation,
hashing, and timing. Reuse Expo for Android device APIs. Every chapter of the
book records a library review and a code review, so “write it in Zig” does not
become “reimplement every library.”

The source itself was drafted module by module with code-generating agents.
Work was divided across evaluator, TUI, oracle tests, Git, Android, and review,
with explicit file ownership and shared transport contracts. Generated source
was compiled, compared with the pinned implementation, and reviewed by another
owner. The useful instruction was a falsifiable contract and a failing replay;
asking for plausible-looking Zig was insufficient. Runtime execution never
delegates to Gleam or looks up pre-recorded answers.

Show a real ownership failure: a historical `!int_add` changed to `!ello λ`
after the user typed new text. AST labels borrowed a reusable terminal buffer.
The PTY test caught behavior that a stateless evaluator test could never see.
Copying retained input into session-owned storage fixed it. Another trace test
caught cached frame symbols borrowing analysis memory that the next edit freed;
snapshot serialization now owns its symbols.

The documentation's source appendix is generated from the canonical code and
contains file hashes. Reconstruct it into a separate directory and build it.
This catches a different form of drift: an explanation that teaches code no
longer used by the actual binary.

## 7. Measure the 10 ms target honestly — 3 minutes

State the timing boundary on the slide before showing a number. A reducer-only
duration differs from input-to-render duration, which differs from visible
terminal response. Measure a release build, use a monotonic clock, and record
hardware, terminal dimensions, sample count, warmup, and workload.

The measurement harness needed review as well: decoding PTY chunks between
reads contaminated a time labelled pre-decode. Receive the full frame and take
the timestamp before running the VT observer. Recheck startup origins and stale
frames before blaming the implementation for a difference.

Show the generated benchmark report rather than typing a remembered number.
Discuss median, high percentiles, maximum, and threshold breaches. A target for
each interaction cannot be justified by an average. Include queries and edits
whose cost grows with history size.

The retained final desktop campaign has 12,800 unfiltered native wall samples:
p50 0.356 ms, p99 2.465 ms, maximum 8.834 ms. Actual PTY samples peaked at
4.950 ms and the ready-hub profile at 1.742 ms. Standalone Escape still took
40.691 ms under the pinned ambiguity policy. Show the report's separate
performance pass and strict compatibility failure together.

Profiling guides optimizations. Keep immutable Git objects cached; give mutable
refs explicit freshness. Avoid process startup inside hot loops, but measure
startup separately. Re-run semantic and buffer comparisons after optimization.

One measured follow-up found discarded JSON frames still retained in the
session arena. A caller-owned output arena now separates those frames from
temporary layout and editor history; its reset stays inside the timed interval.
Keep the previous outliers and remeasure the fixed code. Changing the lifetime
is an implementation fix; deleting slow samples would change the experiment.
Paired thread-CPU samples help inspect a slow wall sample, but wall time alone
controls the threshold. Retain both arrays and every outlier.

Interactive Git queries now suspend onto a worker with its own arena. The UI
acknowledges the key and keeps polling while the query runs, then copies the
finished result and resumes the interpreter. Show both key-response and
query-completion timings. Moving work off the UI thread improves responsiveness;
it does not turn a long query into a 10 ms query.

Hub testing exposed another boundary mistake: reducer tests started with an
empty cache, while the real shell starts a package-ledger pull. Add a local HTTP
hub and seeded package profile, validate content hashes, and exercise startup
through `gleam run -- tui`. Quiescent frames and transient loading frames are
different observations; name which one the comparison establishes.

Speaker note: only report results from the actual checked-in report. If some
workflows exceed 10 ms, identify them. If only generated reducer frames were
timed, do not call that a physical terminal end-to-end result.

## 8. Native Git and Android expose different boundaries — 2 minutes

Git is a good stress case because parsing, decompression, object lookup, delta
resolution, and query evaluation have different costs. Compare behavior with
the `real-world` EYG work and a trusted Git implementation. List supported
repository layouts. A warm cache must not hide stale branch refs.

For Android, retain the interpreter and replace the host. Expo capabilities
become effect handlers through an explicit bridge. One-shot calls, subscriptions,
background tasks, and UI components need different lifecycles. A capability
inventory makes the gap between installed modules and tested behavior visible.

Cross-compiling a shared library, assembling an APK, and running it on a device
are separate milestones. Explain exactly which happened in the demonstration.

## 9. Demonstration and close — 1 minute plus questions

Run a history query in the actual native TUI. Display the query and revision
beside the recording. Replay a saved generated mismatch, then show the fixed
comparison. End with the verification report, including remaining limits.

The repeatable loop is: pin, generate, compare, reduce, repair, measure. The
oracle turns a large rewrite into a sequence of small, falsifiable claims.

## Rehearsal checklist

- Build the release binary and oracle before the talk; retain the commands and
  hashes in the demonstration notes.
- Run the native tests and differential harness, then open their result files.
- Use `./scripts/verify --setup` for the complete campaign; retain its per-run
  logs and `reports/verification.json`, including strict red qualifications.
- Prepare one saved failure and a small replay trace that demonstrates the
  comparison format without requiring a lucky random seed.
- Regenerate and verify the book source appendix.
- Use an actual TUI capture for the live fallback; label protocol-only replays
  and synthetic repositories clearly.
- Keep unsupported language, TUI, Git, and Android features visible in the final
  report. Do not turn incomplete coverage into a perfect-clone claim.

## 10. Complete optimisation walkthrough

Before means the explicitly named control or disabled mechanism. After means
the current implementation on the same probe. These controlled source ablations
are separate from chronological release comparisons. Each table keeps its
workload, units and timing boundary. Small or negative changes remain visible.
The [raw evidence](slides/evidence/) and [reproduction scripts](slides/benchmarks/)
retain all samples and source hashes. Do not multiply isolated ratios into an
application speedup or treat host fixtures as phone measurements.

### The historical change improved observed tail latency

Layout scratch dies after rendering. The caller owns output frames. Unused annotation walks disappear.  This historical pair bundles changes.

Historical campaigns, 12,800 samples in each.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 0.437 | 0.356 |
| p95 (ms) | 1.319 | 1.008 |
| Maximum (ms) | 61.891 | 8.834 |

Final timing additionally includes output-arena reset and paired clock reads.

Threshold breaches decreased from 5 to 0.

Before binary2cb198 and afterc1d288. This is a bundled source change plus a stricter final timing boundary, so it cannot isolate the effect of scratch allocation from annotation removal. Some individual workloads regressed: arithmetic median .439882→.484952ms. Independent current-code ablations follow. Preserve all raw samples and avoid extrapolating observed maxima into worst-case guarantees.


### The integer fast path has a workload tradeoff

Safe integer operands use native arithmetic with widened intermediates.  The ablation forces the floating compatibility path for the same program.

Controlled ablation, 1,000-step recursive sum, 300 samples.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 2.785 | 3.637 |
| p95 (ms) | 7.038 | 9.967 |
| Maximum (ms) | 92.937 | 138.712 |

Already-parsed IR evaluation. Parsing, startup and arena reset are excluded.

Observed median increased. No timing win on this workload.

Engine.evalTrusted on already parsed IR, excludes parsing/process startup/JSON encoding; execution arena resets before timer and retains capacity. Ten warmup iterations per process. No samples filtered.
Workload: arithmetic.eyg. Expected answer 500500. No samples removed. Before variant no-i64. These are host measurements.

[Recorded measurement](slides/evidence/core-android.json), deck slide 16.

### Tail-trace replacement bounds the live chain

At a tail call, replace the current trace instead of linking another frame.  The same suspended sum leaves 2,002 live trace nodes before and 1 after.

Controlled ablation, 1,000-step recursive sum, 300 samples.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 3.092 | 3.765 |
| p95 (ms) | 10.980 | 10.646 |
| Maximum (ms) | 83.669 | 26.606 |

Already-parsed IR evaluation. Parsing, startup and arena reset are excluded.

0.82× ratio of before to after medians. Slower on this workload.

Engine.evalTrusted on already parsed IR, excludes parsing/process startup/JSON encoding; execution arena resets before timer and retains capacity. Ten warmup iterations per process. No samples filtered.
Workload: arithmetic.eyg. Expected answer 500500. No samples removed. Before variant no-tail-trace. These are host measurements. Tail-trace experiment reduces the observable live continuation chain, but retained arena capacity is identical at6,630,200bytes. It does not prove a memory-allocation or runtime speedup.

[Recorded measurement](slides/evidence/core-android.json), deck slide 17.

### Identity checks avoid repeated IR descent

Equal object-map pointers identify the same immutable IR.  Return immediately before recursively comparing its fields.

Closure compared with itself, 200-addition body, 300 samples.

| Metric | Before | After |
| --- | --- | --- |
| Median (µs) | 50.142 | 0.481 |
| p95 (µs) | 239.145 | 0.534 |
| Maximum (µs) | 3066.408 | 736.562 |

Already-parsed IR evaluation. Parsing, startup and arena reset are excluded.

104.24× ratio of before to after medians. Measured on this workload.

Engine.evalTrusted on already parsed IR, excludes parsing/process startup/JSON encoding; execution arena resets before timer and retains capacity. Ten warmup iterations per process. No samples filtered.
Workload: closure-equality.eyg. EYG result True({}), driver checksum 1. No samples removed. Before variant no-ir-identity. These are host measurements.

[Recorded measurement](slides/evidence/core-android.json), deck slide 18.

### Static builtin lookup has a small median difference

Build the lookup table at compile time. Resolve runtime names without scanning the builtin-name list.  The baseline scans that list linearly.

Controlled ablation, 1,000-step recursive sum, 300 samples.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 2.706 | 2.579 |
| p95 (ms) | 4.886 | 5.805 |
| Maximum (ms) | 15.201 | 15.012 |

Already-parsed IR evaluation. Parsing, startup and arena reset are excluded.

1.05× ratio of before to after medians. Measured on this workload.

Engine.evalTrusted on already parsed IR, excludes parsing/process startup/JSON encoding; execution arena resets before timer and retains capacity. Ten warmup iterations per process. No samples filtered.
Workload: arithmetic.eyg. Expected answer 500500. No samples removed. Before variant linear-builtins. These are host measurements.

[Recorded measurement](slides/evidence/core-android.json), deck slide 19.

### Streaming UTF16 comparison avoids allocations

Decode UTF8 into UTF16 code units as the comparison advances.  Stop at the first difference. No temporary UTF16 arrays.

Controlled ablation, 31 alternating batches.

| Metric | Before | After |
| --- | --- | --- |
| Median (µs) | 27.365 | 2.643 |
| p95 (µs) | 34.565 | 4.877 |
| Max avg (µs) | 40.795 | 6.747 |

Amortised time per stated workload. Setup excluded. Exact output bytes match.

10.35× lower median cost.

Monotonic wall time, 31 alternating before/after batches, one warmup per mode, no samples removed. Per-workload times divide batch elapsed by iterations; they are amortised batch timings, not individual tail latencies. Temporary arena reset is timed for allocation-producing kernels. Input/document/closure setup is outside timing.
Workload: 121 pair comparisons over 11 strings with ASCII, BMP, supplementary characters and combining marks.
Before: Materialize two UTF-16 arrays with libc allocation, then compare. After: Stream UTF-16 code units, stopping on the first difference. UTF16 baseline uses libc temporary allocation on a valid UTF8 corpus. These ratios cannot be multiplied into an end-to-end application claim.

[Recorded measurement](slides/evidence/util.json), deck slide 20.

### Binary search narrows Unicode property lookup

Search the sorted property-range table by codepoint.  The baseline scans ranges linearly. The segmentation result stays identical.

Controlled ablation, 31 alternating batches.

| Metric | Before | After |
| --- | --- | --- |
| Median (µs) | 9.361 | 1.711 |
| p95 (µs) | 11.298 | 2.649 |
| Max avg (µs) | 11.559 | 5.542 |

Amortised time per stated workload. Setup excluded. Exact output bytes match.

5.47× lower median cost.

Monotonic wall time, 31 alternating before/after batches, one warmup per mode, no samples removed. Per-workload times divide batch elapsed by iterations; they are amortised batch timings, not individual tail latencies. Temporary arena reset is timed for allocation-producing kernels. Input/document/closure setup is outside timing.
Workload: Segment one mixed-script string containing ASCII, combining sequences, emoji ZWJ, flags, Indic and CJK.
Before: Linear scan of sorted Unicode ranges with early stop. After: Binary search over the same generated Unicode range table. These ratios cannot be multiplied into an end-to-end application claim.

[Recorded measurement](slides/evidence/util.json), deck slide 21.

### Binary search narrows Unicode case mapping

Search the sorted case map for each scalar.  The baseline scans the same map. Both return identical uppercase text.

Controlled ablation, 31 alternating batches.

| Metric | Before | After |
| --- | --- | --- |
| Median (µs) | 6.588 | 1.546 |
| p95 (µs) | 7.885 | 2.165 |
| Max avg (µs) | 8.077 | 2.747 |

Amortised time per stated workload. Setup excluded. Exact output bytes match.

4.26× lower median cost.

Monotonic wall time, 31 alternating before/after batches, one warmup per mode, no samples removed. Per-workload times divide batch elapsed by iterations; they are amortised batch timings, not individual tail latencies. Temporary arena reset is timed for allocation-producing kernels. Input/document/closure setup is outside timing.
Workload: Uppercase one mixed-script string; same Unicode property lookup in both modes.
Before: Linear scan of sorted case mappings with early stop. After: Binary search over the same case map. These ratios cannot be multiplied into an end-to-end application claim.

[Recorded measurement](slides/evidence/util.json), deck slide 22.

### Stored document lengths avoid repeated traversal

Compute a document node’s flat length when building the document.  Layout reads that field instead of walking the same subtree again.

Controlled ablation, 31 alternating batches.

| Metric | Before | After |
| --- | --- | --- |
| Median (µs) | 517.110 | 12.497 |
| p95 (µs) | 578.985 | 21.947 |
| Max avg (µs) | 699.085 | 23.916 |

Amortised time per stated workload. Setup excluded. Exact output bytes match.

41.38× lower median cost.

Monotonic wall time, 31 alternating before/after batches, one warmup per mode, no samples removed. Per-workload times divide batch elapsed by iterations; they are amortised batch timings, not individual tail latencies. Temporary arena reset is timed for allocation-producing kernels. Input/document/closure setup is outside timing.
Workload: Render an already built shared document DAG, seven nested doubled groups, width 80; document construction excluded.
Before: Recursively count grapheme lengths for each text/line/group layout decision. After: Read precomputed Doc.length for each layout decision. These ratios cannot be multiplied into an end-to-end application claim.

[Recorded measurement](slides/evidence/util.json), deck slide 23.

### Early free-name deduplication avoids repeated reification

Collect each free variable once before rebuilding captured bindings.  The baseline repeats reification then deduplicates canonical definitions.

Controlled ablation, 31 alternating batches.

| Metric | Before | After |
| --- | --- | --- |
| Median (µs) | 31.990 | 19.222 |
| p95 (µs) | 56.752 | 33.818 |
| Max avg (µs) | 60.306 | 46.407 |

Amortised time per stated workload. Setup excluded. Exact output bytes match.

1.66× lower median cost.

Monotonic wall time, 31 alternating before/after batches, one warmup per mode, no samples removed. Per-workload times divide batch elapsed by iterations; they are amortised batch timings, not individual tail latencies. Temporary arena reset is timed for allocation-producing kernels. Input/document/closure setup is outside timing.
Workload: Capture one closure whose body contains 128 references to x; same canonical reified IR.
Before: Keep all repeated occurrences, reify each, then use the existing canonical definition deduplication. After: Deduplicate free names while walking IR, reify each distinct free binding once. These ratios cannot be multiplied into an end-to-end application claim.

[Recorded measurement](slides/evidence/util.json), deck slide 24.

### ReleaseFast reduces full evaluation time

Debug retains runtime checks. ReleaseFast optimises the same source and removes those checks.  This times a full recursive evaluation.

Host full evaluation, 300 per build.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 44.254 | 2.829 |
| p95 (ms) | 81.833 | 5.954 |
| Maximum (ms) | 409.071 | 17.055 |

Parsing, startup and reset excluded. The 10 ms TUI gate is separate.

15.65× ratio of before to after medians. Same source and expected answer.

Controlled build configuration comparison on host Linux, Zig 0.14.1. This is full Engine.evalTrusted execution of a tail-recursive sum from 1 through 1000. Both builds return 500500. It is not cooperative TUI key dispatch or an Android device result.

Parse IR before timing. Reset the execution arena before timing and retain capacity. Exclude parser, startup, JSON encoding and arena reset. Ten warmups per process precede each 100-sample wave. Seed 20261028 chooses order across three waves. All 300 raw wall samples per build remain, including maxima.

Before Debug executable SHA256 cceb29b37e75416cbfb0687fa31a7ea2fbf5cd87b4e25ddcb2bc2302313359c6. After ReleaseFast executable SHA256 94c3520d3d2d19eb776bb109b5bcb07672907df77fb7b8de40f83987d92b99dc. Both interpreter source SHA256 7499911d154dc8f51476a42caf7be94d17eae2293709cf6665d0141ca56a2095. Workload SHA256 1098fc52b2a8ab5f66a96a2d659935f1037b7997a0b2ae5911db769171d9b587.

All raw arrays, source hashes, executable hashes, build configurations and wave ordering appear in docs/slides/evidence/debug-release.json at core[name=release-fast-build].raw_ns and the adjacent metadata.

[Recorded measurement](slides/evidence/debug-release.json), deck slide 25.

### Cell interning avoids repeated JSON maps

Hash each symbol and style combination. Reuse one immutable JSON cell object for every identical terminal cell. Each encoded symbol belongs to the output allocator. The JSON encoder still emits the same complete array on the wire.

Empty 80x24 frame, 400 per condition.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 0.630 | 0.190 |
| p95 (ms) | 1.642 | 0.624 |
| Maximum (ms) | 3.144 | 3.253 |

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

Median speedup 3.32x. Wire bytes remain unchanged.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.cell_interning. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 0, "max_ms": 3.144434, "mean_ms": 0.75911759, "p50_ms": 0.629638, "p95_ms": 1.642473, "p99_ms": 2.729371, "samples": 400}. After {"breaches_10ms": 0, "max_ms": 3.253426, "mean_ms": 0.2815023525, "p50_ms": 0.189833, "p95_ms": 0.623641, "p99_ms": 1.540867, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/tui.zig#L87. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

[Recorded measurement](slides/evidence/tui.json), deck slide 26.

### Cell array reservation avoids growth copies

The viewport fixes the number of cells. Reserve that many JSON array slots before appending. This avoids intermediate capacity growth and array copies. Cell maps and the resulting frame remain identical.

Empty 80x24 frame, 400 per condition.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 0.199 | 0.182 |
| p95 (ms) | 0.599 | 0.569 |
| Maximum (ms) | 2.415 | 1.981 |

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

9% lower median. Tails vary across percentiles.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.cell_array_reservation. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 0, "max_ms": 2.414765, "mean_ms": 0.275506065, "p50_ms": 0.199366, "p95_ms": 0.599461, "p99_ms": 1.177692, "samples": 400}. After {"breaches_10ms": 0, "max_ms": 1.981466, "mean_ms": 0.257625935, "p50_ms": 0.181774, "p95_ms": 0.568566, "p99_ms": 1.623231, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/tui.zig#L84. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

[Recorded measurement](slides/evidence/tui.json), deck slide 27.

### Frame storage separates temporary and retained data

Build layout in a scratch arena. Copy the finished frame into caller owned output storage. Reset discarded output inside the timed interval. Retain session storage for editor history and deliberately retained snapshots. The baseline keeps temporary layout and frame output in the session arena.

30 history items, 400 per condition.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 0.474 | 0.289 |
| p95 (ms) | 1.677 | 1.258 |
| Maximum (ms) | 5.499 | 3.480 |

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

After 16 discarded frames. 6,437,544 retained bytes become 0.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.frame_allocation_lifetime. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 0, "max_ms": 5.499299, "mean_ms": 0.646193135, "p50_ms": 0.474276, "p95_ms": 1.676845, "p99_ms": 2.998192, "samples": 400}. After {"breaches_10ms": 0, "max_ms": 3.479567, "mean_ms": 0.44721604, "p50_ms": 0.288898, "p95_ms": 1.258309, "p99_ms": 2.208388, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/tui.zig#L2511. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

Separate session-capacity check after 16 discarded frames: before 6437544 bytes of additional retained arena capacity, after 0 bytes. This checks session growth after warmup and does not claim zero allocation or zero total process memory. Both timing conditions include output reset and paired clock reads.

[Recorded measurement](slides/evidence/tui.json), deck slide 28.

### Unused annotation walks add work to every frame

The renderer reads analysis directly. Copying annotations into every editable node and clearing them across history adds unused tree walks. The ablation restores those walks. Both conditions retain the legacy fields so this probe isolates traversal cost and excludes the smaller Node layout benefit.

30 history items, 400 per condition.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 0.497 | 0.483 |
| p95 (ms) | 1.273 | 1.371 |
| Maximum (ms) | 4.610 | 3.984 |

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

2.9% lower median. No p95 improvement in this probe.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.unused_annotation_walks. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 0, "max_ms": 4.610156, "mean_ms": 0.6249748075, "p50_ms": 0.497143, "p95_ms": 1.273327, "p99_ms": 2.180183, "samples": 400}. After {"breaches_10ms": 0, "max_ms": 3.984125, "mean_ms": 0.6363064075, "p50_ms": 0.482883, "p95_ms": 1.370626, "p99_ms": 2.657793, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/tui.zig#L2026. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

Both conditions include restored legacy annotation fields. This isolates the old traversal work and excludes representation-size savings from removing the fields. Small median differences are not proof of a robust improvement. The mean and p95 are slightly worse after on this run.

[Recorded measurement](slides/evidence/tui.json), deck slide 29.

### Draft analysis cache reuses unchanged type analysis

Hash the editable tree and immutable runtime scope identity. Reuse prior inference when the key remains unchanged. Recompute after edits, scope changes or explicit invalidation. Keep the cached type graph in its own arena. This turns stable frame rendering into a hash check.

50 record literals, 400 per condition.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 4.292 | 0.383 |
| p95 (ms) | 6.738 | 0.969 |
| Maximum (ms) | 14.978 | 22.576 |

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

Median speedup 11.20x. An after outlier exceeds 10ms.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.draft_analysis_cache. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 3, "max_ms": 14.978259, "mean_ms": 4.5655574875, "p50_ms": 4.291994, "p95_ms": 6.738032, "p99_ms": 8.796989, "samples": 400}. After {"breaches_10ms": 1, "max_ms": 22.576379, "mean_ms": 0.5410544399999999, "p50_ms": 0.383373, "p95_ms": 0.969368, "p99_ms": 2.013368, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/tui.zig#L2032. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

The enabled diagnostic workload retains one 22.576379ms maximum. This new large static-frame probe differs from the original 12800-sample interaction campaign. The original under 10ms result applies only to its recorded workloads.

[Recorded measurement](slides/evidence/tui.json), deck slide 30.

### History values reuse their formatted text

An evaluated history value stays immutable. Cache its formatted document text with the viewport width. Reuse that text on subsequent frames. A width change invalidates the layout. A separate arena owns each cached result rather than retaining temporary formatting in the session arena.

50 record result, 400 per condition.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 0.827 | 0.604 |
| p95 (ms) | 1.684 | 1.285 |
| Maximum (ms) | 5.372 | 2.605 |

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

27% lower median. Width changes invalidate the cache.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.history_value_pretty_cache. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 0, "max_ms": 5.371877, "mean_ms": 0.9452339725000001, "p50_ms": 0.827479, "p95_ms": 1.683977, "p99_ms": 2.484523, "samples": 400}. After {"breaches_10ms": 0, "max_ms": 2.605121, "mean_ms": 0.7032510825, "p50_ms": 0.604249, "p95_ms": 1.284708, "p99_ms": 1.866142, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/tui.zig#L2885. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

[Recorded measurement](slides/evidence/tui.json), deck slide 31.

### Frozen scopes trade conversion for graph copying

Cache the inferred environment for an immutable runtime scope by identity. Give every new inference run a private graph copy so unification cannot mutate the cached graph. This replaces repeated runtime value conversion with graph copying. The extra lookup and copy can cost more for small values.

35 bindings, 400 analyses per condition.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 1.362 | 1.426 |
| p95 (ms) | 2.909 | 2.869 |
| Maximum (ms) | 8.819 | 6.225 |

Fresh inference on annotated TUI IR. Includes scope and effect text. Separate from key response.

Small records: 4.7% slower median. Large values: 1.1% faster median.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.immutable_scope_cache. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 0, "max_ms": 8.819259, "mean_ms": 1.6355941425, "p50_ms": 1.361983, "p95_ms": 2.909253, "p99_ms": 4.855311, "samples": 400}. After {"breaches_10ms": 0, "max_ms": 6.225381, "mean_ms": 1.6001473275, "p50_ms": 1.42603, "p95_ms": 2.869124, "p99_ms": 4.193911, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/inference.zig#L81. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Fresh inference on annotated TUI IR. Includes scope and effect text. Separate from key response.

Second regime, retained separately: five 50-record list values and 20 references to the same complex value. Source docs/slides/evidence/tui-large-context.json, cases.immutable_scope_cache. Exact before {"breaches_10ms": 0, "max_ms": 6.901261, "mean_ms": 1.646331835, "p50_ms": 1.401341, "p95_ms": 3.110116, "p99_ms": 4.562757, "samples": 400}. Exact after {"breaches_10ms": 0, "max_ms": 5.241199, "mean_ms": 1.5142711174999999, "p50_ms": 1.385542, "p95_ms": 2.543175, "p99_ms": 3.318203, "samples": 400}. Large report SHA256 103f57aab916f7fada5a774614cecf34f4fdcf91ccca9bdb37749fde1728adb2. Both regimes remain visible. These results do not establish a universal speedup.

[Recorded measurement](slides/evidence/tui.json), deck slide 32.

### Type text reuse adds overhead in these probes

After inference stabilizes the graph, use each resolved type pointer as a key for rendered type text. Reuse the result for later annotations of that type. Both conditions record cache entries. Before disables lookup and reuse. Extra lookup can exceed the cost of rendering simple types.

35 bindings, 400 analyses per condition Reuse disabled versus enabled.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 1.350 | 1.399 |
| p95 (ms) | 2.570 | 3.346 |
| Maximum (ms) | 12.934 | 11.633 |

Fresh inference on annotated TUI IR. Includes scope and effect text. Separate from key response.

Small records: 3.6% slower median. Large values: 7.6% slower median.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.rendered_type_memoization. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 1, "max_ms": 12.934153, "mean_ms": 1.5630750775, "p50_ms": 1.350403, "p95_ms": 2.56971, "p99_ms": 5.133989, "samples": 400}. After {"breaches_10ms": 3, "max_ms": 11.632757, "mean_ms": 1.6967052425, "p50_ms": 1.399278, "p95_ms": 3.345967, "p99_ms": 6.520736, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/inference.zig#L685. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Fresh inference on annotated TUI IR. Includes scope and effect text. Separate from key response.

Second regime, retained separately: five 50-record list values and 20 references to the same complex value. Source docs/slides/evidence/tui-large-context.json, cases.rendered_type_memoization. Exact before {"breaches_10ms": 0, "max_ms": 6.771089, "mean_ms": 1.561812795, "p50_ms": 1.351265, "p95_ms": 2.729516, "p99_ms": 4.226179, "samples": 400}. Exact after {"breaches_10ms": 0, "max_ms": 9.331494, "mean_ms": 1.8068577124999998, "p50_ms": 1.453813, "p95_ms": 3.748013, "p99_ms": 5.364699, "samples": 400}. Large report SHA256 103f57aab916f7fada5a774614cecf34f4fdcf91ccca9bdb37749fde1728adb2. Both regimes remain visible. These results do not establish a universal speedup.

Ablation model: before disables cache READ and REUSE. Both conditions retain common cache PUT bookkeeping. This isolates reuse benefits and does not represent a completely cache-free historical implementation. The exact source diff is retained.

[Recorded measurement](slides/evidence/tui.json), deck slide 33.

### Completion scopes reuse rendered text

A single inference run often annotates many nodes with the same immutable lexical environment. Cache the completion name and type list by environment identity. Build it once with shadowing rules and reuse it for later annotations. Both conditions record entries. Before disables lookup and reuse.

35 bindings, 400 analyses per condition Reuse disabled versus enabled.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 2.669 | 1.681 |
| p95 (ms) | 6.227 | 3.564 |
| Maximum (ms) | 13.945 | 7.840 |

Fresh inference on annotated TUI IR. Includes scope and effect text. Separate from key response.

37% lower median. Same completion scope and types.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.rendered_scope_memoization. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 4, "max_ms": 13.94488, "mean_ms": 3.230729395, "p50_ms": 2.668678, "p95_ms": 6.226738, "p99_ms": 8.969049, "samples": 400}. After {"breaches_10ms": 0, "max_ms": 7.84029, "mean_ms": 1.9279429025, "p50_ms": 1.681495, "p95_ms": 3.563529, "p99_ms": 5.603969, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/inference.zig#L692. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Fresh inference on annotated TUI IR. Includes scope and effect text. Separate from key response.

Ablation model: before disables cache READ and REUSE. Both conditions retain common cache PUT bookkeeping. This isolates reuse benefits and does not represent a completely cache-free historical implementation. The exact source diff is retained.

[Recorded measurement](slides/evidence/tui.json), deck slide 34.

### Ordinary frames omit unused inference projections

Ordinary frame rendering consumes types, errors and paths. It leaves completion scopes and effect text disabled. Picker analyses still request the richer projection they consume. The ablation collects the extra metadata while keeping the visible terminal frame unchanged.

50 literals, 400 forced fresh analyses.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 4.601 | 4.630 |
| p95 (ms) | 9.350 | 10.958 |
| Maximum (ms) | 16.581 | 39.109 |

Complete frame and output reset, forcing fresh inference on both sides. Setup excluded.

Empty scope: 0.6% slower median. Large scope: 3.2% faster median.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.omit_unused_scope_effect_projections. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 13, "max_ms": 16.581227, "mean_ms": 5.16555383, "p50_ms": 4.601016, "p95_ms": 9.350041, "p99_ms": 12.470608, "samples": 400}. After {"breaches_10ms": 27, "max_ms": 39.109414, "mean_ms": 5.562108125, "p50_ms": 4.630135, "p95_ms": 10.957679, "p99_ms": 17.494201, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/tui.zig#L2036. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Complete frame and output reset, forcing fresh inference on both sides. Setup excluded.

Second regime, retained separately: five 50-record list values and 20 references to the same complex value. Source docs/slides/evidence/tui-large-context.json, cases.omit_unused_scope_effect_projections. Exact before {"breaches_10ms": 8, "max_ms": 25.064295, "mean_ms": 3.5991707925, "p50_ms": 2.969447, "p95_ms": 7.463318, "p99_ms": 11.102933, "samples": 400}. Exact after {"breaches_10ms": 1, "max_ms": 11.474559, "mean_ms": 3.1917060025, "p50_ms": 2.875014, "p95_ms": 5.553294, "p99_ms": 7.434756, "samples": 400}. Large report SHA256 103f57aab916f7fada5a774614cecf34f4fdcf91ccca9bdb37749fde1728adb2. Both regimes remain visible. These results do not establish a universal speedup.

[Recorded measurement](slides/evidence/tui.json), deck slide 35.

### Picker matching folds the query once

Case fold the query once per matching pass. Fold each candidate name and compare its prefix with the same folded query. The baseline folds the query again for every candidate. Keep matching Unicode behavior identical.

Builtin picker, 400 frames per condition.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 0.408 | 0.368 |
| p95 (ms) | 2.189 | 0.938 |
| Maximum (ms) | 5.784 | 2.288 |

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

10% lower median. Same matching choices and cells.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.picker_query_casefold_once. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 0, "max_ms": 5.784366, "mean_ms": 0.628292005, "p50_ms": 0.408366, "p95_ms": 2.189, "p99_ms": 2.981534, "samples": 400}. After {"breaches_10ms": 0, "max_ms": 2.288401, "mean_ms": 0.4544561225, "p50_ms": 0.368356, "p95_ms": 0.938433, "p99_ms": 1.65312, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/tui.zig#L860. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Complete frame and output reset. Setup excluded. No key dispatch or JSON encoding.

[Recorded measurement](slides/evidence/tui.json), deck slide 36.

### ANSI encoding emits style changes only

Track the previous visible cell style. Emit SGR resets and color or modifier sequences only when the style changes. Continue emitting every visible symbol and preserve wide character continuation handling. The baseline emits the complete style before every visible cell.

Nested program, 400 frames per condition.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 0.083 | 0.065 |
| p95 (ms) | 0.328 | 0.387 |
| Maximum (ms) | 1.332 | 3.978 |

Complete ANSI frame generation and output reset. Setup excluded. Byte output intentionally changes.

10,401 bytes before. 2,235 bytes after.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.ansi_style_change_elision. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 0, "max_ms": 1.3321, "mean_ms": 0.1288934675, "p50_ms": 0.082592, "p95_ms": 0.327935, "p99_ms": 0.73184, "samples": 400}. After {"breaches_10ms": 0, "max_ms": 3.978095, "mean_ms": 0.13330010250000002, "p50_ms": 0.064895, "p95_ms": 0.386709, "p99_ms": 1.270278, "samples": 400}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/tui.zig#L118. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Complete ANSI frame generation and output reset. Setup excluded. Byte output intentionally changes.

The nested-frame byte count is 10401 before and 2235 after. Exact ANSI bytes intentionally differ. Six real TUI frames and one explicit synthetic style case passed VT-cell and effective-SGR-per-character trace equivalence. The supplementary trace covers dim, all modifier bits, RGB/indexed colors and underline colors. Pyte 0.8.2 cannot parse colon underline-color SGR. Remove those sequences only for that observer and check them in the exact supplemental trace. Evidence docs/slides/evidence/tui-ansi-parity.json, SHA256 7df32a6b014f13473f07fc27442ee16eb194e6fd80cdd14bb24b220d2506d9ab.

[Recorded measurement](slides/evidence/tui.json), deck slide 37.

### Buffered JSON output batches system calls

Wrap the identical JSON encoder in a buffered writer. Flush once after the complete response newline. Batching short writes avoids repeated system calls. The baseline writes directly to stdout. Encoding, full response bytes and decoded values remain identical.

One frame, 16 pipe replies per condition.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 75.283 | 2.545 |
| p95 (ms) | 98.936 | 10.191 |
| Maximum (ms) | 98.936 | 10.191 |

Request send to reply newline, before JSON decoding. Includes encoding and pipe transport.

Median speedup 29.58x. 211,262 response bytes on both sides.

Before means one mechanism disabled in a generated standalone ReleaseFast binary. After means the mechanism enabled. These are ablations, not invented chronological measurements. Every other mechanism remains enabled. Do not multiply the speedups.

Four AB/BA blocks alternate order. Every internal row has 400 samples per condition except buffered JSONL, which has 16. Preserve all samples and all threshold breaches. Source report: docs/slides/evidence/tui.json, cases.buffered_jsonl_output. Raw wall arrays: samples_ns.before and samples_ns.after. Percentiles use nearest rank.

Exact measured values: before {"breaches_10ms": 16, "max_ms": 98.935703, "mean_ms": 77.356840375, "p50_ms": 75.282762, "p95_ms": 98.935703, "p99_ms": 98.935703, "samples": 16}. After {"breaches_10ms": 1, "max_ms": 10.190638, "mean_ms": 3.490896875, "p50_ms": 2.544767, "p95_ms": 10.190638, "p99_ms": 10.190638, "samples": 16}.

The production executable SHA256 is c1d28826315b4e8fc353157c2f3c1c363e889a2f90a545c60980451a268a0edd. The generated ablation executable SHA256 is 96bb17a1ce34e20105146a4617e7a3d61bb0fc61590ae2e941fa300e59f436f4. Standard report SHA256 is d427455fccf369b91900f3883a035a1ac27481b358a8ff06df13de8f0f6a1c69.

Implementation: https://github.com/CrowdHailer/eyg-lang/blob/tui-zig/packages/zig_runtime/src/main.zig#L86. Reproduction scripts and source diffs accompany the evidence.

All canonical TUI frames, enabled-variant frames and disabled-variant frames compared exactly before timing. The standard campaign covers 354 frame states across the 12 internal probes. For type/scope diagnostics, setup includes actual retained bindings and annotated source. The unused-projection ablation intentionally changes metadata that ordinary rendering does not consume.

Request send to reply newline, before JSON decoding. Includes encoding and pipe transport.

Both conditions emit exactly 211262 response bytes. The timer ends after complete response newline reception, before json.loads. This row includes serialization and pipe transport, which the original desktop dispatch/frame benchmark excludes. All 16 before samples exceed 10ms. One enabled sample exceeds10ms at 10.190638ms.

[Recorded measurement](slides/evidence/tui.json), deck slide 38.

### Decoded objects and delta bases share a bounded cache

Cache bytes by object ID and pack offset. Reuse decoded parents, trees and delta bases. Admit at most 512 entries and 16 MiB of accounted bytes. Read mutable refs afresh.

README.md history, limit 20, scan cap 200.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 48.466 | 26.899 |
| p95 (ms) | 476.125 | 330.547 |
| Maximum (ms) | 1899.855 | 1086.881 |

100 pairs. Engine: realtime nanoTimestamp. Paired monotonic roundtrips also retained.

The median fell 44.5%. Current maximum remained 1,086.881 ms..

Before removes cache admission while keeping the same decoding and validation logic. After retains immutable objects within a fresh Repository for each request. The request searches README.md history with result limit 20 and scan_limit 200 at the pinned real-world commit. Repeated tree, parent and delta-base lookups can reuse reconstructed bytes. The native cache stops admitting at 512 entries or 16 MiB accounted bytes. It is not an LRU and this budget does not cap total arena memory. HEAD, refs and config stay outside this cache. The long retained maxima are query completion costs. They cannot support an under 10 ms UI claim.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

The standalone engine driver subtracts std.time.nanoTimestamp wall CLOCK_REALTIME readings around git.request, after JSON parse and before serialization. It assumes no realtime-clock correction during short pairs. Paired Python time.perf_counter_ns monotonic roundtrips include JSON and transport and remain alongside these engine samples. Each request starts a fresh Repository and request arena. OS file caches are warm.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git.zig#L207
Evidence: docs/slides/evidence/git.json, case decoded-object-cache
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 39.

### One validated index load serves every object in a query

Read pack indexes once per Repository. Keep fanout, object IDs and offsets in memory. Verify each index checksum once. Reuse those bytes for every packed lookup in the request.

20 full commit records, fresh Repository.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 12.473 | 1.847 |
| p95 (ms) | 15.255 | 2.684 |
| Maximum (ms) | 20.407 | 3.632 |

100 pairs. Engine: realtime nanoTimestamp. Paired monotonic roundtrips also retained.

The median fell 85.2%. Index checksum checks remain enabled..

Before clears the loaded-index list and reloads and SHA-checks index files on every locate call. After uses the indexed flag so one Repository shares its validated index bytes. Both run the same 20-record first-parent history query and return identical full records. Each request creates a fresh Repository, so this is reuse within a query rather than a claim of a persistent cross-query index cache. Disk caches are warm. Index checksums remain enabled on both sides.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

The standalone engine driver subtracts std.time.nanoTimestamp wall CLOCK_REALTIME readings around git.request, after JSON parse and before serialization. It assumes no realtime-clock correction during short pairs. Paired Python time.perf_counter_ns monotonic roundtrips include JSON and transport and remain alongside these engine samples. Each request starts a fresh Repository and request arena. OS file caches are warm.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git.zig#L141
Evidence: docs/slides/evidence/git.json, case lazy-index-load
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 40.

### Binary lookup did not improve this full-query median

Object IDs occupy a sorted table. Before scans the complete table. After selects a fanout bucket and binary-searches its 20-byte IDs. The rest of the query stays the same.

20 full commit records, same packed corpus.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 1.750 | 1.818 |
| p95 (ms) | 2.445 | 2.895 |
| Maximum (ms) | 4.391 | 16.836 |

100 pairs. Engine: realtime nanoTimestamp. Paired monotonic roundtrips also retained.

The current median rose 3.9%. This query showed no lookup win..

Before linearly scans each complete index table. After uses the production fanout-bounded binary search. The comparison therefore disables both the search algorithm and bucket restriction together. The separate fanout slide isolates bucket restriction alone. The asymptotic search reduces comparisons on large tables, but the measured20-record full query did not improve. Inflation, hashing, filesystem work and allocation remain in this timing boundary. Retain the negative observation and its 16.836 ms current maximum. Do not advertise an isolated logarithmic speedup from these full-query numbers.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

The standalone engine driver subtracts std.time.nanoTimestamp wall CLOCK_REALTIME readings around git.request, after JSON parse and before serialization. It assumes no realtime-clock correction during short pairs. Paired Python time.perf_counter_ns monotonic roundtrips include JSON and transport and remain alongside these engine samples. Each request starts a fresh Repository and request arena. OS file caches are warm.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git.zig#L173
Evidence: docs/slides/evidence/git.json, case binary-index-search
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 41.

### Fanout bounds did not improve this query median

The first hash byte selects a bucket. A 256-entry cumulative table gives its bounds. Binary search stays inside that slice. Before searches the whole sorted index instead.

20 full commit records, binary search on both sides.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 1.693 | 1.841 |
| p95 (ms) | 2.585 | 2.614 |
| Maximum (ms) | 3.545 | 4.468 |

100 pairs. Engine: realtime nanoTimestamp. Paired monotonic roundtrips also retained.

The current median rose 8.7%. Fanout showed no query win here..

Both sides use binary search. Before sets bounds to the whole object-ID table. After reads lower and upper bounds from the pack-index fanout table using the first OID byte. For evenly distributed hashes, a bucket has about 1/256 of the entries, although actual bucket sizes vary. This reduces the search interval without removing object validation. On this corpus the full-query median increased from 1.6927595 ms to 1.8406145 ms. These data establish no measured end-to-end benefit for fanout. Larger-index or lookup-only experiments would test a different claim.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

The standalone engine driver subtracts std.time.nanoTimestamp wall CLOCK_REALTIME readings around git.request, after JSON parse and before serialization. It assumes no realtime-clock correction during short pairs. Paired Python time.perf_counter_ns monotonic roundtrips include JSON and transport and remain alongside these engine samples. Each request starts a fresh Repository and request arena. OS file caches are warm.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git.zig#L178
Evidence: docs/slides/evidence/git.json, case fanout-bounds
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 42.

### Metadata rejection avoids unnecessary tree reads

Check time, message and author first. Reject nonmatches before path lookup. Read current and parent trees only for commits that pass those cheap metadata filters.

100 commits, absent author and a path filter.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 7.957 | 5.726 |
| p95 (ms) | 10.353 | 8.347 |
| Maximum (ms) | 13.695 | 11.474 |

100 pairs. Engine: realtime nanoTimestamp. Paired monotonic roundtrips also retained.

The median fell 28.0%. Every request still scans 100 commits..

The query combines path dark/git/read.eyg with an author substring __absent_slide_probe__ and scan_limit 100. No commit matches that author. Before performs current/parent path-tree work before testing metadata. After rejects each commit immediately after parsing its metadata, avoiding those path-tree reads. Both return an empty result and still traverse the same 100 commits. This intentionally selective workload demonstrates filter ordering, not a guarantee for queries whose metadata filters accept every commit. The current 11.474 ms maximum remains visible.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

The standalone engine driver subtracts std.time.nanoTimestamp wall CLOCK_REALTIME readings around git.request, after JSON parse and before serialization. It assumes no realtime-clock correction during short pairs. Paired Python time.perf_counter_ns monotonic roundtrips include JSON and transport and remain alongside these engine samples. Each request starts a fresh Repository and request arena. OS file caches are warm.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git.zig#L568
Evidence: docs/slides/evidence/git.json, case cheap-filters-first
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 43.

### A result limit avoids traversing the remaining history

Stop once enough matching records exist. Before visits the rest of the history and returns the same prefix. Keep scan_limit as a separate safety bound for selective queries.

20 records from 430 first-parent commits.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 22.055 | 1.886 |
| p95 (ms) | 29.356 | 2.600 |
| Maximum (ms) | 48.885 | 2.901 |

100 pairs. Engine: realtime nanoTimestamp. Paired monotonic roundtrips also retained.

The median fell 91.4% by avoiding work after the twentieth record..

The pinned real-world revision has 430 first-parent commits. The query asks for 20 unfiltered full records. Before continues visiting commits until history ends while retaining only the requested prefix. After exits as soon as 20 matching records exist. Both preserve record order and return the same prefix. This measures avoided traversal and decode work, not faster parsing of each visited commit. Filtered queries may need many more than 20 visits before accumulating 20 matches. The separate scan_limit still caps exploration.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

The standalone engine driver subtracts std.time.nanoTimestamp wall CLOCK_REALTIME readings around git.request, after JSON parse and before serialization. It assumes no realtime-clock correction during short pairs. Paired Python time.perf_counter_ns monotonic roundtrips include JSON and transport and remain alongside these engine samples. Each request starts a fresh Repository and request arena. OS file caches are warm.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git.zig#L564
Evidence: docs/slides/evidence/git.json, case stop-at-result-limit
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 44.

### Object streams avoid copying an entire pack

Seek to the packed object offset. Feed its compressed stream through a buffered reader. Decode only that object and required bases. Before copies the whole pack for each packed decode.

3 packed commits at real-world revision ancestor 20.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 14.622 | 1.016 |
| p95 (ms) | 31.593 | 2.453 |
| Maximum (ms) | 101.636 | 40.543 |

100 pairs. Engine: realtime nanoTimestamp. Paired monotonic roundtrips also retained.

The median fell 93.1%. The current maximum was still 40.543 ms..

The request returns three full records from 321279a62d9dd3a144e5bed803646ddf7d2fa994, the twentieth first-parent ancestor of the pinned real-world revision. Before loads the complete containing pack into the request arena for each packed-object call, then decodes from the selected offset. After seeks to the offset and lets the buffered zlib reader consume the selected stream and required delta bases. Object checksums and returned records are identical. This ablation exposes excess read/copy/allocation work. The current 40.542576 ms maximum is retained and prevents a universal under 10 ms query-completion claim.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

The standalone engine driver subtracts std.time.nanoTimestamp wall CLOCK_REALTIME readings around git.request, after JSON parse and before serialization. It assumes no realtime-clock correction during short pairs. Paired Python time.perf_counter_ns monotonic roundtrips include JSON and transport and remain alongside these engine samples. Each request starts a fresh Repository and request arena. OS file caches are warm.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git.zig#L238
Evidence: docs/slides/evidence/git.json, case stream-packed-objects
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 45.

### The delta header supplies the output allocation size

Decode the target length first. Reserve its output capacity once. Copy contiguous base spans into that buffer. Before starts empty and grows the array as each span arrives.

1 MiB target, 64 copies of 16 KiB.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 1.074 | 0.376 |
| p95 (ms) | 2.547 | 0.849 |
| Maximum (ms) | 34.895 | 1.541 |

100 pairs. Kernel: monotonic std.time.Timer. Allocation included. Teardown excluded.

The median fell 65.0%. The same delta and range checks run..

This is a monotonic kernel benchmark using the actual applyDelta implementation. Both base and target are 1 MiB, reconstructed by 64 indexed 16 KiB copy operations. Before changes ArrayList initialization to zero capacity. After reserves target_size, read from the Git delta header. Both include target allocation, instruction processing and a full equality check inside the timer. Arena teardown falls outside the timer. Both keep base-size, target-size, copy-range and output-size validation. This fixture isolates allocation strategy and does not establish a 20-record history-query speedup.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

Kernel clock is std.time.Timer, which is monotonic. Allocation is included and arena destruction is excluded. Results are validated as described.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git.zig#L377
Evidence: docs/slides/evidence/git.json, case delta-output-preallocation
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 46.

### Incremental SHA avoids a full header and body copy

Feed the Git header and body to SHA-1 in chunks. Before builds one combined buffer. After hashes borrowed slices without that extra allocation and full body copy.

SHA-1 of one 1 MiB Git blob.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 1.963 | 1.623 |
| p95 (ms) | 2.786 | 2.347 |
| Maximum (ms) | 4.452 | 4.310 |

100 pairs. Kernel: monotonic std.time.Timer. Allocation included. Teardown excluded.

The median fell 17.3% for this 1 MiB hashing kernel..

The kernel hashes the exact bytes blob 1048576 followed by NUL and a 1 MiB body, with the required space between kind and size. Before allocates and concatenates the complete header and body. After feeds the fixed complete header and body to incremental SHA-1. Python hashlib independently verifies the digest. The monotonic timer includes concatenation allocation/copy on the baseline side and SHA work on both sides. Production verifyObject also formats and streams individual header fields. This kernel isolates the copy choice and is not an end-to-end production verifier or history-query measurement.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

Kernel clock is std.time.Timer, which is monotonic. Allocation is included and arena destruction is excluded. Results are validated as described.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git.zig#L457
Evidence: docs/slides/evidence/git.json, case incremental-object-hash
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 47.

### Fast compression made only a small kernel difference

Zig fast uses DEFLATE level 4. Default uses level 6. Smaller match-search budgets can reduce compression work. Both emit standard zlib streams for the same input bytes.

1 MiB repeated source phrase, compression only.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 2.632 | 2.566 |
| p95 (ms) | 3.792 | 3.668 |
| Maximum (ms) | 8.888 | 9.674 |

100 pairs. Kernel: monotonic std.time.Timer. Allocation included. Teardown excluded.

Median improvement was 2.5%. Both outputs occupied 3,124 bytes..

Both modes compress a 1 MiB highly compressible fixture built from a repeated source-code phrase. In Zig 0.14.1, .fast aliases DEFLATE level 4 and .default aliases level 6. Level4 reduces lazy and chain match-search budgets. Every encoded result decompresses back to the original bytes after the timer stops. The monotonic kernel includes output allocation and compression, while excluding filesystem calls, fsync and arena teardown. The median moved only 2.5%, encoded sizes were equal at 3,124 bytes, and the current maximum increased from 8.888425 ms to 9.673995 ms. Treat this as a small fixture-dependent difference rather than a general compression win.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

Kernel clock is std.time.Timer, which is monotonic. Allocation is included and arena destruction is excluded. Results are validated as described.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git_write.zig#L101
Evidence: docs/slides/evidence/git.json, case fast-write-compression-kernel
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 48.

### The compression level also changes full write cost

Keep SHA, file publication and fsync unchanged. Change only DEFLATE level 6 to level 4. Remove the target object before each request so every sample performs a fresh write.

Fresh 1 MiB loose object with fsync and rename.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 6.852 | 5.659 |
| p95 (ms) | 14.758 | 11.512 |
| Maximum (ms) | 43.743 | 13.760 |

100 pairs. Engine: realtime nanoTimestamp. Paired monotonic roundtrips also retained.

The median fell 17.4%. Both Git object files occupied 3,137 bytes..

This uses the real write_blob request, not only the compression kernel. Both variants derive the content address, form the Git object header, compress the same 1 MiB text, write a temporary loose object, fsync and rename it. Before uses .default, level 6. After uses production .fast, level 4. The target object is removed before every measured request, outside the driver timer, so an existing-object shortcut cannot contaminate the result. Engine timing includes repository setup and full publication but excludes JSON parse, serialization and test setup. Both return the same independently calculated object ID. Encoded files are 3,137 bytes for both modes on this fixture. The current 13.760 ms maximum remains above 10 ms.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

The standalone engine driver subtracts std.time.nanoTimestamp wall CLOCK_REALTIME readings around git.request, after JSON parse and before serialization. It assumes no realtime-clock correction during short pairs. Paired Python time.perf_counter_ns monotonic roundtrips include JSON and transport and remain alongside these engine samples. Each request starts a fresh Repository and request arena. OS file caches are warm.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git_write.zig#L101
Evidence: docs/slides/evidence/git.json, case fast-write-compression-end-to-end
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 49.

### Existing immutable objects can skip publication

Derive the content address first. If its object exists, read and verify it. Return the ID without recompression, fsync or rename. Otherwise publish the new compressed object normally.

Same 1 MiB blob, absent object versus existing object.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 5.392 | 4.959 |
| p95 (ms) | 7.113 | 7.625 |
| Maximum (ms) | 11.242 | 11.232 |

100 pairs. Engine: realtime nanoTimestamp. Paired monotonic roundtrips also retained.

The median improved 8.0%, while p95 increased..

Both sides request the same 1 MiB blob through the current implementation. Before removes its target object before each timed call, forcing compression, fsync and rename. After keeps the identical valid object in a separate isolated repository, allowing the normal existence check to reuse it. Both compute the requested raw-object SHA first. The existing path still reads, inflates and verifies stored data, so it does not bypass integrity checks. A corrupt existing object still fails. Median fell from 5.3918925 ms to 4.9585965 ms, but p95 rose from 7.113465 ms to 7.62515 ms and maxima remained about 11.24 ms. This demonstrates a small reuse benefit with a mixed tail result.

All numbers are milliseconds from 100 randomized paired measurements after 3 warmups per side. Seed is 0x455947. Every sample, including outliers, remains in docs/slides/evidence/git.json. Before is a controlled source ablation or explicitly stated workload state, not a historical release. Complete returned values matched for each pair. Native source hashes remained unchanged. Canonical Git reference is f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9. These measurements do not establish physical-key or Android-device latency.

The standalone engine driver subtracts std.time.nanoTimestamp wall CLOCK_REALTIME readings around git.request, after JSON parse and before serialization. It assumes no realtime-clock correction during short pairs. Paired Python time.perf_counter_ns monotonic roundtrips include JSON and transport and remain alongside these engine samples. Each request starts a fresh Repository and request arena. OS file caches are warm.

Source: https://github.com/CrowdHailer/eyg-lang/blob/090a8a5d4658f19f854bf55d3309650f895d5355/packages/zig_runtime/src/git_write.zig#L87
Evidence: docs/slides/evidence/git.json, case existing-object-write-reuse
Reproduction: docs/slides/benchmarks/git/README-reproduce.md

[Recorded measurement](slides/evidence/git.json), deck slide 50.

### Cooperative slices bound one blocking interval

Run the VM for a 1 ms budget. Save its control and continuation. Return to the host, then resume.  Total computation still takes time.

20 equal computations, 690,038 VM steps each.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 117.757 | 1.008 |
| p95 (ms) | 185.500 | 1.215 |
| Maximum (ms) | 277.697 | 6.262 |

Before: 20 full calls. After: 1,605 slice calls. Host responsiveness probe.

Maximum caller block. 277.697 ms before, 6.262 ms after.

Every variant runs the same finite recursive computation, returns 112507500 and executes 690038 VM steps. The baseline runs synchronously. The production policy uses a 1 ms budget and checks the clock every 128 VM steps. Statistics describe each interval during which the caller remains blocked. The sliced variant therefore has 1605 interval samples across 20 equal computations. Total completion time is a separate measurement, and slicing does not claim to make it faster. A slice cannot preempt a long individual native builtin or a blocking external effect.

[Recorded measurement](slides/evidence/host.json), deck slide 51.

### Amortised clock checks reduce scheduler overhead

Read the elapsed clock once per 128 VM steps instead of every step.  The budget check costs less, with coarser interruption points.

20 equal computations, total evaluation time.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 127.616 | 81.104 |
| p95 (ms) | 152.162 | 91.859 |
| Maximum (ms) | 217.803 | 137.425 |

Controlled host observation. Variants ran in fixed phases, not randomized order.

127.616 ms before. 81.104 ms after.

Both variants use a 1 ms cooperative budget and execute 690038 VM steps per computation. A control added only to the scratch source changes the clock mask from 0 to 127, comparing a check on every step with a check every 128 steps. The table measures full completion time, separately from individual caller blocking intervals. Fixed phase order limits the experiment. This local run does not establish a universal causal percentage. The report retains every interval and total duration.

[Recorded measurement](slides/evidence/host.json), deck slide 52.

### Git workers release the caller while the query runs

Copy the request into worker storage. Publish completion atomically.  Copy the result back and resume the suspended EYG computation.

20 host calls with an explicit 20 ms I/O fixture delay.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 22.338 | 0.062 |
| p95 (ms) | 23.676 | 0.331 |
| Maximum (ms) | 26.029 | 0.469 |

Table measures caller return. Completion remains a separate, longer operation.

Completion median. 22.422 ms before, 22.688 ms after.

Both policies execute the same real native Git operation, with the same explicit 20 ms fixture delay before the pinned-history query. The table compares synchronous caller blocking with acknowledgment that the worker has started. These are host API measurements, not physical TUI frame or Android device measurements. Query completion has separate medians and raw intervals. Reference-counted worker storage has an independent lifetime, allowing detached shutdown without freeing memory the worker still uses.

[Recorded measurement](slides/evidence/host.json), deck slide 53.

### Hub workers release the caller during verified fetches

Snapshot the cache for a worker. Fetch and verify module content.  Merge after completion, then resume the suspended EYG computation.

20 host calls with an explicit 20 ms I/O fixture delay.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 21.909 | 0.072 |
| p95 (ms) | 24.996 | 0.142 |
| Maximum (ms) | 30.764 | 0.429 |

Table measures caller return. Completion remains a separate, longer operation.

Completion median. 21.910 ms before, 22.382 ms after.

Both policies execute the same real native hub operation, using a local HTTP fixture with an explicit 20 ms response delay and actual content verification. The table compares synchronous caller blocking with acknowledgment that the worker has started. These are host API measurements, not physical TUI frame or Android device measurements. Completion has separate medians and raw intervals. Reference-counted worker storage has an independent lifetime, allowing detached shutdown without freeing memory the worker still uses.

[Recorded measurement](slides/evidence/host.json), deck slide 54.

### Verified module reuse avoids fetch and initialization

Cache modules under immutable content IDs. Retain their pure initialized values.  A hit skips fetching, parsing and evaluating the same module.

20 lookups of the same pure sum(1500) module.

| Metric | Before | After |
| --- | --- | --- |
| Median (µs) | 18953.384 | 0.550 |
| p95 (µs) | 31018.194 | 3.211 |
| Maximum (µs) | 51510.748 | 7.749 |

Controlled 2 ms GET fixture. Cold control clears the module cache before each lookup.

Timed module GETs. 20 before, 0 after.

The module computes 1125750 in both conditions. Initial warmup occurs outside the timer. Cold mode clears cached modules while retaining the same host and interpreter, then fetches, verifies, decodes and evaluates the same source on each lookup. Warm mode resolves the cached initialized value. These controlled host lookup timings do not promise remote network latency. Failed initialization remains an observable break that must preserve oracle behaviour.

[Recorded measurement](slides/evidence/host.json), deck slide 55.

### Known package names avoid redundant ledger pulls

Resolve known names from the ledger view. An unknown name triggers one incremental refresh.  Keep content-pinned references stable.

20 known-name lookups with a 2 ms GET fixture.

| Metric | Before | After |
| --- | --- | --- |
| Median (µs) | 2086.932 | 0.081 |
| p95 (µs) | 2199.581 | 0.096 |
| Maximum (µs) | 2208.289 | 0.290 |

A new-name miss makes 2 GETs. Repeating that known lookup makes 0 GETs.

Known-name GETs: 20 before, 0 after. New release: cursor 5 advances to 6.

The baseline forces cache.refresh before every lookup of a known package name. Production reuses its current ledger view. Both policies discover the seeded new release with two incremental GET requests, advance the cursor from 5 to 6, and make zero GET requests when the lookup repeats. This measures avoided requests. It does not guarantee that every lookup of an already-known name polls for every possible upstream publication. Explicit version and content pins provide reproducibility.

[Recorded measurement](slides/evidence/host.json), deck slide 56.

### The self-pipe wakes a blocked event loop

The signal handler writes a byte. Poll watches the pipe and terminal.  A resize wakes the loop immediately instead of awaiting a periodic timeout.

20 OS signal trials, 100 ms periodic-poll control.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 97.039 | 0.151 |
| p95 (ms) | 186.260 | 0.497 |
| Maximum (ms) | 446.474 | 0.632 |

Python OS mechanism probe with actual SIGWINCH and select. No physical-display claim.

Signal-to-return median. 97.039 ms before, 0.151 ms after.

This controlled counterfactual compares 100 ms periodic polling with a self-pipe, using actual SIGWINCH and select in a Python host probe. It does not claim that a historical Zig release used this exact polling policy. The native event loop uses a nonblocking resize self-pipe and polls terminal and pipe descriptors, with short polling while work remains pending. Escape retains the oracle-compatible 40 ms ambiguity deadline. All scheduling outliers remain in the report, including 446.474 ms for the periodic control.

[Recorded measurement](slides/evidence/host.json), deck slide 57.

### Nonjoining close returns while native IO waits

Before close waits for active calls. After close retires IDs immediately. The active call keeps its pointer until its worker returns.

25 ms blocked IO, 30 calls per policy.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 25.823 | 0.184 |
| p95 (ms) | 51.195 | 0.780 |
| Maximum (ms) | 73.920 | 1.038 |

Host JVM fixture. Device untested. Call return only, not IO completion.

The caller returns before IO completes.

Controlled lifecycle-policy ablation on host JVM17. Both variants use the actual NativeSessions ownership manager and the same deterministic NativeBackend fixture. The baseline waits for each active session lock before retiring IDs. Production close retires IDs and marks active calls for cancellation without joining their native IO. The active call owns its pointer until it returns.

The fixture releases an already-entered native call after a scheduled 25 ms delay. It does not model faster networking. Measure the close caller return, not the eventual IO completion. Run 30 samples per policy after five warmups. All raw wall samples remain. Hardware, Android UI scheduling and phone latency are untested.

Production Kotlin SHA256 7ea9ce6d58ecd8f8bf03cbaf077c4378cf970a54ac69902f6b493dcc7274ea34. Blocking baseline Kotlin SHA256 7d4b13c2fbabbfd265db3f604d7475be8825454b495e67356ac2340ba21165af. Fixture source SHA256 7b54870a0aadaa7d79715a64465d4853a742d2ee5ebe54ce998f07d993a089f8. The reproduction scripts generate the single-policy source variation without modifying canonical source.

All raw arrays and summary values appear in docs/slides/evidence/core-android.json at lifecycle[workload=active].raw_ns. The report preserves production Kotlin SHA256. The source generator and build logs identify the host classes.

[Recorded measurement](slides/evidence/core-android.json), deck slide 58.

### Worker disposal removes idle cleanup from close

Before close frees idle sessions. After close queues their disposal on a worker outside the caller thread.

Caller return, 30 calls per policy.

| Metric | Before | After |
| --- | --- | --- |
| Median (ms) | 25.203 | 0.398 |
| p95 (ms) | 25.808 | 1.393 |
| Maximum (ms) | 34.734 | 1.506 |

Host JVM fixture. Device untested. The fixture destructor waits 25 ms.

The caller returns before destruction. completes.

Controlled idle-disposal-policy ablation on host JVM17. Both variants use the actual NativeSessions ownership manager. The baseline runs idle native.destroy directly in close. Production uses its dedicated disposer executor after retiring session IDs. This shifts cleanup latency away from the close caller. It does not reduce the destructor work or claim that memory is already freed when close returns.

The deterministic NativeBackend destructor sleeps 25 ms. Measure caller return only. Await destruction after each observation so no sessions leak into later samples. Run 30 samples per policy after five warmups. Preserve all raw wall samples. Android device performance and actual arena-deallocation latency are untested.

Production Kotlin SHA256 7ea9ce6d58ecd8f8bf03cbaf077c4378cf970a54ac69902f6b493dcc7274ea34. Synchronous-free baseline Kotlin SHA256 b44d0543b41a0f1c0679fbae44950fce7e0ec047d295dc1a72e5408186fee5de. Fixture source SHA256 7b54870a0aadaa7d79715a64465d4853a742d2ee5ebe54ce998f07d993a089f8.

All raw arrays and summary values appear in docs/slides/evidence/core-android.json at lifecycle[workload=idle].raw_ns. The report preserves production Kotlin SHA256. The source generator and build logs identify the host classes.

[Recorded measurement](slides/evidence/core-android.json), deck slide 59.

## 11. Architecture and correctness boundaries

The iterative VM, persistent values, explicit effect bridge, generated Unicode
and fixed inspection constants define the implementation and compatibility
contract. A missing equivalent native baseline does not justify an invented
speedup. Retained input copies, snapshot symbol ownership, source provenance,
sticky cancellation and compiler corrections preserve behaviour. Bounded pure
callbacks and durable background entrypoints add capability and lifecycle
constraints. Their resource limits do not establish an Android wall-time bound.

The earlier `real-world` branch reports aggregate EYG algorithm and compiler
measurements. It covers constant powers, fixed Huffman tables, windowed
back-reference copies, indexed binary access, pack fanout, lazy imports,
compiler fixes, short-read ownership, pure-kernel compilation and decoded-object
caching. Those historical observations combine changes and timing boundaries.
The native kernel and query tables above isolate the current implementation
where an equivalent control exists.

The original 12,800 dispatch samples met their 10 ms budget. The additional
forced-analysis and query-completion probes preserve larger outliers. Three
oracle hangs, 56 malformed-input oracle crashes and three HTTP constructor
differences keep strict compatibility qualification false. Physical standalone
Escape retains its approximately 40 ms ambiguity deadline. APK dependency
access still blocks Android device validation.
