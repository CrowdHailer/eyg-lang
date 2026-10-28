# Core and Android responsiveness ablations

These probes explain implementation choices with controlled source ablations. They are not reconstructed historical releases. `prepare_probes.py` copies canonical runtime sources into an ignored work directory and changes exactly one policy per variant. All source and executable hashes and unfiltered wall samples appear in `evidence.json`.

`run_probes.py` parses EYG once outside the timer, then measures `Engine.evalTrusted`. Its arena resets before each timed call and retains capacity. This differs from the desktop TUI performance gate, which times dispatch, full frame construction and output-arena reset. These full-recursion results do not replace that interactive gate. Every run verifies the final result.

## Reproduction

From `packages/zig_runtime`, use a quiet host. The default package-root detection searches the script ancestors for both `src/interpreter.zig` and `build.zig`, including from `docs/slides/benchmarks/core-android/`. Override it with `--package-root` when needed.

```sh
python3 docs/slides/benchmarks/core-android/prepare_probes.py
python3 docs/slides/benchmarks/core-android/build_probes.py
python3 docs/slides/benchmarks/core-android/prepare_lifecycle.py --jdk /path/to/jdk17 --gradle-cache /path/to/gradle-user-home
python3 docs/slides/benchmarks/core-android/run_probes.py
python3 docs/slides/benchmarks/core-android/run_probes.py --debug-only
python3 docs/slides/benchmarks/core-android/build_probes.py --trace-depth --variant optimized --variant no-tail-trace
python3 docs/slides/benchmarks/core-android/run_trace_depth.py
```

To check source preparation without compiling or timing, run `prepare_probes.py --work-dir /path/to/scratch` and `prepare_lifecycle.py --prepare-only --work-dir /path/to/scratch`. Every script also supports `--help`.

Zig 0.14.1 is required. The Kotlin probe uses cached compiler 2.2.21, standard library 2.2.21, reflection 2.2.10, coroutines 1.8.1 and annotations 13.0, matching the existing Android lifecycle test. It does not fetch dependencies.

## Measured choices

| Choice | Baseline policy | Production policy | Mechanism |
|---|---|---|---|
| Native integer operations | Force JavaScript floating fallback | Use native integer path when both values are safe | Avoid conversions and floating truncation checks while retaining JavaScript-compatible slow handling |
| Tail traces | Always push another trace | Replace the head trace on a tail call | Bound the live continuation trace that effects and inspectors traverse |
| Closure IR equality | Always descend structurally | Return equal for identical IR object maps | Skip a complete tree walk when both closures share the same body |
| Builtin lookup | Linear name checks | `std.StaticStringMap` | Use the compiler-generated static lookup for every builtin name resolution |
| Runtime close with blocked IO | Join active calls first | Retire IDs and retain live native ownership until workers return | Keep cancellation/lifecycle work independent of blocked IO |
| Idle runtime destruction | Free arenas synchronously in close | Schedule disposal on a worker | Keep potentially expensive deallocation off the lifecycle thread |
| Release build | Debug checks and unoptimised code | ReleaseFast | Compiler optimisation and build configuration |

The arithmetic workload sums 1 through 1,000 using tail recursion. The equality workload compares a closure with itself whose body contains 200 nested additions. Each core comparison has 300 samples per policy, in three waves with seeded order and ten warmups per process. The single-result checks cover the benchmark input, not every oracle observable under disabled policies.

The Kotlin workloads run the actual `NativeSessions` class on host JVM17. A deterministic fixture delays native IO or destruction by 25 ms. There are 30 samples per policy after five warmups. These numbers quantify close-call responsiveness in that fixture. They are not Android device measurements and do not mean native IO itself completed sooner.

The recorded native-integer and tail-trace timing results are negative on this workload. Preserve them. Source-level expectations do not establish a speedup. The trace-depth probe separately demonstrates 2,002 live continuation nodes becoming 1 while total retained arena capacity remains exactly 6,630,200 bytes.

## Android changes without a before and after speedup claim

`Dispatchers.IO` routes native evaluate/resume away from the UI thread. Shared JNI/C ABI reuses the language implementation. Bounded synchronous callbacks add a fixed-memory and step-limited capability, not a measured optimisation of an existing callback path. Durable background entrypoints, atomic cancellation, explicit handles and callback cleanup establish capability and ownership contracts.

`android/native-benchmark.json` measures current host C ABI costs. Its loaded predecessor and quiet rerun differ in host scheduling, so they do not establish an implementation speedup. The file before mobile extensions uses a different bridge with unchanged common engine sources, so its difference does not isolate an optimisation either. APK dependency resolution and hardware validation remain blocked.

The fixed builtin inspector dictionary is generated compatibility data. No prior dynamic native dictionary implementation exists to time honestly. The full continuation-inspection oracle comparison verifies changing frames and values. Agent-authored source and the generated book appendix concern development and reproducibility rather than runtime acceleration.
