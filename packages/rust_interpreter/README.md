# EYG Rust Interpreter

A Rust implementation of the [EYG](https://eyg.run) interpreter.
Reads EYG programs encoded as dag-json IR and executes them using a
continuation-passing-style (CPS) evaluator with persistent environments.

## Build

```sh
cargo build --release
```

## Usage

```sh
# Execute a dag-json IR program
eyg-run program.json

# Execute with explicit effect handlers
eyg-run program.json --effects handlers.json
```

The `Log` effect is handled automatically — log messages are printed to stderr,
and execution continues with a unit reply.

### Effect Handlers

Provide a JSON array of handler objects:

```json
[
  { "label": "Ask", "lift": {}, "reply": { "string": "yes" } }
]
```

Each handler matches one `perform` in order. The `reply` value is
deserialized and fed back to the continuation.

## Project Layout

```
src/
  main.rs              CLI entry point (eyg-run)
  lib.rs               Library root
  interpreter/         CPS interpreter engine
    expression.rs        execute / resume / step
    state.rs             continuation & stack types
    value.rs             runtime values (Integer, String, Tagged, Record, …)
    builtin.rs           built-in functions (arithmetic, strings, lists, …)
    break_reason.rs      error / unhandled-effect variants
    cast.rs              value → concrete type helpers
    value_json.rs        JSON ↔ Value round-trip
    env.rs               environment helpers
  ir/
    mod.rs             Re-exports from eyg-ir crate
crates/
  eyg-ir/              Shared IR types (Node, Expr, dag-json serde)
tests/                 Integration & unit tests
testdata/              Fixture files for effect-handler tests
```

## Development

```sh
make check   # cargo test --workspace + cargo clippy
make test    # cargo test --workspace
make lint    # cargo clippy --workspace -- -D warnings
```

Tests cover:
- **evaluation_suite** — shared spec suites from `spec/evaluation/` (core, builtins, effects)
- **ir_suite** — IR round-trip from `spec/ir_suite.json`
- **builtin_tests** — unit tests for built-in functions
- **cli_tests** — end-to-end CLI integration tests
