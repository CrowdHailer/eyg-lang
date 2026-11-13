# EYG in Zig

A native interpreter and structural terminal shell, tested against the actual
Gleam implementation on `next-tui`. The executable starts the TUI when run
without arguments, as `gleam run -- tui` does.

The oracle is pinned to `be502aa03df926a8f9df474a0a7fe16c8fb14fbd`.
The Git reference is `real-world` at
`f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9`.
Neither oracle checkout is changed by the test adapters.
Native unit fixtures are pinned to the same oracle in tests/fixtures; newer
root-spec features such as Datalog queries are not supported by this runtime.

## Build and use

Use Zig **0.14.1**. The wrapper uses an installed compiler or installs the
versioned `ziglang` package into this package's ignored `work/` directory.

```sh
cd packages/zig_runtime
./scripts/zig build -Doptimize=ReleaseFast
./zig-out/bin/eyg
./zig-out/bin/eyg eval -c '!int_add(20, 22)'
./scripts/zig build test
```

The TUI requires terminal input and output. Ctrl+Q exits; bracketed paste
inserts a program; Enter executes it. Arrow keys navigate; `n` inserts an
integer, `s` a string, `j` a builtin, and `q` a file import. The displayed
selection and type information follow the pinned oracle.

The interpreter uses canonical EYG DAG-JSON IR. The source parser, lexical
closures, curried primitives, delimited multi-shot effect continuations,
Unicode grapheme operations and type/effect inference are native Zig.
The runtime uses Zig's standard library for compression, hashes, Ed25519,
HTTP/TLS, allocation and terminal I/O. No Gleam, JavaScript, Git subprocess or
OpenSSL dependency is needed to run the desktop binary.

## Reproduce the oracle checks

Development tests additionally require Git, Gleam 1.19.2, Bun, and Python 3.
For terminal tests, install the pinned test dependencies in `tests/requirements.txt`.

```sh
./scripts/prepare-oracles.sh
python3 -m pip install --target ../../work/test-dependencies -r tests/requirements.txt
python3 tests/differential.py --programs 5000 --syntax 1000 --traces 100
python3 tests/differential_input.py --cases 1000
python3 tests/pty_parity.py --help
python3 tests/differential_inference.py --help
python3 tests/differential_computer.py --help
```

`reports/` contains machine-readable measurements and counterexamples. A
mismatch is a failed gate. Every generated trace compares the initial buffer
and the buffer after **every** event, including symbol, display width,
foreground/background, modifiers, underline color and link. Failing traces
are reduced and saved with their seed. Replay one with
`tests/differential.py --replay reports/failures/<file>.json`.

The JSONL adapter is `eyg --protocol`. It provides `eval`, `parse`, `diagnostic`,
`input`, `tui`, `bench_tui` and `git` operations. This adapter exposes the native
implementations; it does not invoke the oracle.

## Performance

```sh
python3 tests/benchmark.py --iterations 100 --oracle
```

The benchmark reports p50/p95/p99/maximum and fails if any measured native
dispatch-plus-frame sample reaches 10 ms. Its correctness gate must refer to
the same executable hash and a complete passing differential campaign. Real
PTY tests separately measure key-to-ANSI-frame time, including transport.
An isolated Escape deliberately waits for the oracle's 40 ms escape-sequence
ambiguity timer; that physical-key latency cannot meet a universal 10 ms goal.

Native Git effects run on a worker thread in the TUI, with a running indicator,
completion resumption and cancellation of waiting. Initial feedback and final
query completion are separate measurements. Large results still take time to
convert and render; filesystem durability and OS scheduling can produce tail
latencies. Saved reports retain outliers.

## Git, Android, book and talk

- [Git API and verification](git/README.md): native objects, packs/deltas,
  filtered history, remotes, trees, commits and compare-and-swap refs.
- [Android app](android/README.md): shared Zig interpreter through JNI and an
  Expo phone-effects host. The APK build currently needs the environment to
  allow `repo.reactnative.dev`, which hosts React Native's Android artifact.
- [Crafting an EYG interpreter](docs/book.md): concise chapters for experienced
  programmers new to Zig, library decisions and implementation reviews.
- [Complete source listings](docs/source-listings.md): hash-checked files from
  which the real runtime can be extracted and built.
- [Talk](docs/talk.md): oracle design, generated programs and interactions,
  counterexample reduction, native acceleration and performance evidence.

Use `docs/book_sources.py --help` to regenerate or reconstruct the source
appendix. A source reconstruction is separately built and tested; it is not
merely illustrative pseudocode.
