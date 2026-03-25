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

## Resolved Development Issues

### Brittle Test binary Path (Fixed)
Integration tests in `tests/cli_tests.rs` now use the `CARGO_BIN_EXE_eyg-run` environment variable (with a fallback) to locate the interpreter binary, making tests more portable across build configurations.

### Flaky Concurrent Tests (Fixed)
CLI tests now use unique temporary file paths based on process and thread IDs and ensure cleanup after execution, preventing race conditions during parallel test runs.
