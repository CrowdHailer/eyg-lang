# Rust Interpreter Limitations

This document tracks known issues, architectural limitations, and bugs in the Rust interpreter.

## Critical Issues (Severity: High)

### Integer Arithmetic Panics (Overflow)
The interpreter uses native Rust `i64` arithmetic operators (`+`, `-`, `*`, `/`) without overflow protection. Large integer inputs can cause the interpreter process to crash/panic.
- **Affected Builtins**: `int_add`, `int_subtract`, `int_multiply`, `int_divide`, `int_absolute`.
- **Reproducible Case**: `i64::MIN / -1` and `i64::MAX + 1` both trigger panics in standard Rust execution.
- **Fix Needed**: Switch to `checked_` or `wrapping_` arithmetic and return an error value to the guest program rather than crashing the host.

### Interleaved Log Effects
In the CLI runner (`main.rs`), the `Log` effect handler is only executed *after* all explicit command-line effect handlers have been processed in sequence. 
- **Bug**: If a program performs a `Log` effect *before* or *interspersed* with other effects that have handlers provided via `--effects`, the runner will encounter the `Log` effect while expecting a different label, causing it to exit with an "unexpected effect" error.
- **Fix Needed**: The effect handling loop in `main.rs` should handle `Log` natively and resume immediately, while keeping track of the current position in the explicit `effect_handlers` list.

## Development Issues (Severity: Medium)

### Brittle Test binary Path
Integration tests in `tests/cli_tests.rs` hard-code the path to `./target/debug/eyg-run`. 
- **Issue**: This assumes the binary has been built in debug mode and the current working directory is the package root. 
- **Fix Needed**: Use the `env!("CARGO_BIN_EXE_eyg-run")` macro provided by Cargo to locate the binary correctly during `cargo test`.

### Flaky Concurrent Tests (Fixed Tmp Files)
CLI tests write to fixed file paths like `/tmp/eyg_test_integer.json`.
- **Issue**: Since Rust runs tests in parallel by default, multiple tests can overwrite the same file simultaneously, leading to non-deterministic test failures.
- **Fix Needed**: Use a crate like `tempfile` to create unique temporary files for each test case.
