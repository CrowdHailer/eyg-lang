# Utility optimisation ablations

Run from a checkout with Zig 0.14.1 and Python 3:

```sh
python3 run.py --root /path/to/packages/zig_runtime --output /tmp/eyg-utility-ablation
```

Use `--build-only` and later `--measure-only` with the same output directory to
keep compilation and other benchmarks outside the timing window. Keep the host
quiet during measurement. The runner copies source files, inserts runtime flags
for one algorithm at a time, validates exact output bytes, then records 31
alternating batches per mode. It never edits canonical source files.

These are controlled algorithm ablations, not historical release comparisons.
Per-workload values divide batch wall time by iteration count. They are
amortised costs, not individual interaction maxima. All raw batches and input,
driver and executable hashes remain in the output report.

The cases cover allocation-free UTF16 ordering, binary Unicode property lookup,
binary case-map lookup, cached pretty-document lengths, and free-variable early
deduplication before closure reification. Comparator inputs are valid UTF8.
Document and closure construction stay outside timing. The pretty case is an
already built document DAG with seven doubled levels and width 80. The closure
case has 128 references to one captured integer. Temporary arena reset remains
inside timing for allocation-producing kernels.

Closure free-variable filtering and canonical definition sharing also determine
the observable captured IR. A capture-all baseline would change that IR, so it
is not claimed as an oracle-equivalent performance comparison.
