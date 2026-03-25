# Rust Interpreter Limitations

This document tracks known issues, architectural limitations, and bugs in the Rust interpreter.

## Critical Issues (Severity: High)

### Integer Arithmetic Panics (Overflow)
The interpreter uses native Rust `i64` arithmetic operators (`+`, `-`, `*`, `/`) without overflow protection. Large integer inputs can cause the interpreter process to crash/panic.
- **Affected Builtins**: `int_add`, `int_subtract`, `int_multiply`, `int_divide`, `int_absolute`.
- **Reproducible Case**: `i64::MIN / -1` and `i64::MAX + 1` both trigger panics in standard Rust execution.
- **Fix Needed**: Switch to `checked_` or `wrapping_` arithmetic and return an error value to the guest program rather than crashing the host.

## Resolved Development Issues

### Brittle Test binary Path (Fixed)
Integration tests in `tests/cli_tests.rs` now use the `CARGO_BIN_EXE_eyg-run` environment variable (with a fallback) to locate the interpreter binary, making tests more portable across build configurations.

### Flaky Concurrent Tests (Fixed)
CLI tests now use unique temporary file paths based on process and thread IDs and ensure cleanup after execution, preventing race conditions during parallel test runs.

### Interleaved Log Effects (Fixed)
The CLI runner in `main.rs` now uses a single unified loop to process effects. This allows `Log` effects to be handled automatically even when they are interspersed between explicit effects provided via the `--effects` flag.
