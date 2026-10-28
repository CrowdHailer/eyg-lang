# Porting EYG with an executable oracle

Open the [editable slide deck](https://chatgpt.com/space/page_38b0eecb8da081919a205d2a9b6931cf).
The 67-slide technical deck expands the [talk](../talk.md) with an explanation of
each measured optimisation, its mechanism, and before-and-after results.

[deck.json](deck.json) contains slide text, tables, layouts and speaker notes.
[build-slides.mjs](build-slides.mjs) creates native editable presentation objects
through the Pages presentation callback. It receives the existing presentation
model and authorised image references. The real TUI capture comes from
[the Git-query recording](../../recordings/git-history/eyg-git-history.mp4).

The 45 main performance tables contain **44 controlled comparisons and one
historical TUI comparison**. A separate overview cites earlier aggregate EYG
observations.
A controlled baseline disables or replaces the stated mechanism in a separate
source copy, or uses the explicitly named fixture policy. It is not an invented
previous release. The historical TUI comparison bundles implementation changes
and has a different timing boundary. Neither comparison permits multiplying
individual ratios into an overall speedup.

## Evidence and validation

[evidence/](evidence/) retains raw timing arrays, source and executable hashes,
workloads, sample counts, and diagnostic observations. It includes the utility,
interpreter, TUI, Git and host experiments, plus historical and native/oracle
comparisons. All samples and outliers remain, including neutral and negative
results. Integer arithmetic, tail-trace replacement, type-text caching and some
query lookup policies did not improve the selected median measurements.

Run the standard-library-only validator from `packages/zig_runtime`:

```sh
python3 docs/slides/validate.py
python3 docs/slides/validate.py --help
```

It checks the 67-slide source, all 45 performance tables and their 270 displayed
time values against saved evidence, and verifies local source, evidence and
reproduction inputs. It does not rebuild the runtime, rerun benchmarks, inspect
the saved presentation, or establish semantic equivalence by itself.

## Reproducing measurements

Build the current production binary first. The TUI comparison harness requires
`zig-out/bin/eyg` in addition to its ablation executable:

```sh
./scripts/zig build -Doptimize=ReleaseFast
```

Copy each reproduction bundle into an ignored work directory before preparing
or compiling it. Some preparation scripts, notably the host bundle, generate
source copies and manifests beside themselves. Running them directly under
`docs/slides/benchmarks` would add generated files to the documentation tree.
For example, from `packages/zig_runtime`:

```sh
mkdir -p work/slides/reproduce
cp -R docs/slides/benchmarks/util work/slides/reproduce/util
cp -R docs/slides/benchmarks/core-android work/slides/reproduce/core-android
cp -R docs/slides/benchmarks/tui work/slides/reproduce/tui
cp -R docs/slides/benchmarks/host work/slides/reproduce/host
cp -R docs/slides/benchmarks/git work/slides/reproduce/git
```

Read the copied bundle's README and invoke its scripts from that copied
location. Replace documented script paths with the copied paths and pass the
package or repository root explicitly when appropriate. Use ignored work
locations for generated sources and binaries. Core Android lifecycle probes
also need JDK 17 and the documented cached Kotlin dependencies. Git probes need
the pinned `real-world` history present in the checkout.

Compile every variant before measuring. Keep compiler jobs, rendering and other
benchmark campaigns outside the timing window. Run CPU measurements one at a
time. Preserve the original evidence when trying another seed or workload.

## Timing boundaries and limits

The final desktop campaign measures event dispatch, complete cell-frame
construction and output-arena reset. Its 12800 retained samples have a 0.356 ms
median and an 8.834 ms maximum. JSON encoding, terminal transport and startup
are outside that timer. Physical standalone Escape retains the oracle's
approximately 40 ms ambiguity deadline.

The new comparisons use several explicitly different boundaries:

- Core interpreter probes time evaluation of already parsed IR.
- Utility numbers are amortised batch costs. Their maximum is the largest batch
  average, not an individual interaction maximum.
- TUI probes distinguish frame construction, inference, ANSI encoding and JSONL
  roundtrips. Diagnostic workloads retain samples above 10 ms.
- Git query engine timings use realtime `nanoTimestamp` differences. Paired
  monotonic roundtrips remain beside them. Kernel probes use a monotonic timer.
- Cooperative and worker probes distinguish caller blocking from total
  completion. A faster acknowledgment does not make IO finish sooner.
- Android lifecycle probes run on a host JVM with controlled delays. They do not
  measure phone hardware, OS scheduling or device UI latency.

Strict perfect-clone qualification remains false because of oracle hangs,
malformed-input oracle crashes and HTTP constructor differences. Async query
completion can exceed 10 ms. APK assembly and Android device validation remain
blocked by dependency access. The deck makes bounded, reproducible claims and
does not claim a universal sub-10-ms interaction guarantee.
