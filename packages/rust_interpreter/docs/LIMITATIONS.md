# Rust Interpreter Limitations

This document tracks known issues, architectural limitations, and bugs in the Rust interpreter.

## Integer Arithmetic Panics (Overflow) (Severity: High)
The interpreter uses native Rust `i64` arithmetic operators (`+`, `-`, `*`, `/`) without overflow protection. Large integer inputs can cause the interpreter process to crash/panic.
- **Affected Builtins**: `int_add`, `int_subtract`, `int_multiply`, `int_divide`, `int_absolute`.
- **Reproducible Case**: `i64::MIN / -1` and `i64::MAX + 1` both trigger panics in standard Rust execution.
- **Fix Needed**: Switch to `checked_` or `wrapping_` arithmetic and return an error value to the guest program rather than crashing the host.
