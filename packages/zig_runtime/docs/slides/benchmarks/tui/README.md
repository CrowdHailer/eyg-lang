# TUI optimisation ablations for the EYG talk

These probes disable one optimisation at a time in a generated, separate
ReleaseFast source tree. Production source and its executable remain unchanged.
“Before” means the specified mechanism disabled in this experiment, not an
invented chronological predecessor. Both conditions share one executable and
alternate AB/BA order. Raw samples and outliers remain in `results.json`.

From the runtime package directory, build the production baseline first:

```sh
./scripts/zig build -Doptimize=ReleaseFast
```

Generate and measure the diagnostic executable:

```sh
python3 docs/slides/benchmarks/tui/prepare.py --package "$PWD" --output work/slides/tui-ablation
./scripts/zig build-exe -OReleaseFast work/slides/tui-ablation/src/main.zig \
  -femit-bin=work/slides/tui-ablation/eyg-ablation
python3 docs/slides/benchmarks/tui/measure.py --package "$PWD" --output work/slides/tui-ablation
```

The generator emits exact diffs and source hashes. No full source snapshot is
required to reproduce it. Use `--blocks N --iterations N` to change the sample
count or `--only CASE_NAME` to run one case. Run timings without other compiler
or benchmark processes. This is a managed shared host and repeated wall-clock
runs can vary.

Measurement units differ deliberately:

- `bench_static`: full repeated frame construction, output-arena reset, paired
  wall/thread-CPU clock reads. Setup happens outside samples. No key dispatch.
- `bench_ansi`: full ANSI frame generation and output reset. The byte count is
  preserved alongside every sample.
- `bench_analysis`: fresh inference on annotated TUI IR with completion scopes
  and effect text. This is a diagnostic workload, separate from the key target.
- buffered JSONL: request send through complete reply newline, timestamped
  before JSON decoding. This includes encoding and pipe transport.

Canonical TUI frames, all-optimisations-enabled frames, and each disabled
variant's frames are compared before timing. Type/scope cache flags alter
allocation/reuse, not what inference computes.

The unused-annotation test restores legacy fields in every condition, then
enables/disables the old apply/clear tree walks. It isolates traversal cost and
omits the extra benefit from shrinking the Node representation. The frame
lifetime test restores retention of layout and output in the session arena,
while keeping the final timing/reset boundary on both sides. Its separate
capacity check measures bytes retained after 16 discarded frames.

`historical-and-oracle.json` preserves historical bundle and native/Gleam data.
That older bundle has a different timing boundary, so it must not supply an
independent per-optimisation causal claim.

`--profile large-context` adds a contrasting reuse regime for immutable-scope,
rendered-type and omitted-projection probes. It binds five 50-record list values
and references the same complex type 20 times. It writes
`results-large-context.json`, preserving the original small-input results and
regressions. Both regimes belong in the evidence; neither is a universal bound.

ANSI style elision changes bytes intentionally. Verify effective terminal
output separately:

```sh
./scripts/zig build-exe -OReleaseFast --dep tui \
  -Mroot=docs/slides/benchmarks/tui/ansi_qa.zig \
  -Mtui=work/slides/tui-ablation/src/tui.zig \
  -femit-bin=work/slides/tui-ablation/ansi-qa
python3 docs/slides/benchmarks/tui/check_ansi.py --package "$PWD" --output work/slides/tui-ablation
```

The parity report covers six real TUI frames and one explicit synthetic style
case, including all modifier bits, RGB/indexed colors and underline colors.
Pyte cannot parse the colon underline-color extension, so that extension is
removed only for the Pyte observer and verified independently by an exact
effective-style-per-character trace. Raw ANSI streams are retained with hashes.

Rendered type and scope memoization compare lookup/reuse disabled against
lookup/reuse enabled. Common cache PUT bookkeeping remains in both conditions.
These two probes isolate reuse savings rather than model a fully cache-free
historical predecessor. Original raw reports remain unchanged.
