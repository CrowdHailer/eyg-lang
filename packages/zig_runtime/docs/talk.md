# Porting EYG with an executable oracle

A 25-minute talk with a live demonstration and discussion. The accompanying
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
