# Git optimisation ablations

From `packages/zig_runtime`, build the variants and run the paired comparisons:

```sh
python3 docs/slides/benchmarks/git/build_ablations.py
python3 docs/slides/benchmarks/git/run_ablations.py --samples 100
```

The scripts locate the containing Zig package from their own path. Set
`EYG_SLIDES_PACKAGE=/absolute/path/to/packages/zig_runtime` to override it.
Copy `kernel.zig` beside the builder. A fresh run generates source variants,
compiler logs and binaries under `work/slides/git/`; no canonical source changes.
Do not run timing alongside builds, renders or another benchmark campaign.

Each baseline disables one mechanism in the current source. These are controlled
ablations, not fabricated historical releases. One current query has a separate
baseline pair for each mechanism. All100 samples per side remain in the report,
with paired order randomized from seed0x455947 and3 warmups per side. Comparisons
check complete returned JSON equality. History IDs also match independent Git.

Native driver timings cover `git.request` after JSON parse and before JSON
serialization using `std.time.nanoTimestamp` differences (wall CLOCK_REALTIME).
Monotonic Python roundtrip samples include JSON and transport. Kernels use
`std.time.Timer`, a monotonic clock. The engine timer assumes no realtime clock correction during
the short pairs. The1MiB delta/hash/compression fixture and boundaries
appear in the report and kernel source. Compression verifies every decompressed
result outside the timed interval; SHA checks against Python hashlib.

The engine-versus-roundtrip distinction matters. None of these query or
compression results establish a10ms physical-key or Android-device claim.
The path-cache workload retained a1,899.855ms baseline maximum and1,086.881ms
current maximum. Binary search/fanout did not improve full-query medians on this
small corpus. The report preserves these observations.

`run_ablations_measured.py` is the exact runner used for the retained evidence.
The portable runner differs only in package path discovery. Variant and binary
hashes, source-unchanged checks and all raw timings accompany the evidence.
