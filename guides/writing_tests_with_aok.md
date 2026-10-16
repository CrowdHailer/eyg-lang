---
name: Writing tests with aok
description: Write typed EYG tests with assertions and ordered computer-effect expectations.
---

## Writing a test

A test consists of a record with a `name` and `test` field.
The `test` field is a function returning any value that throws abort in case of failure.

Use `aok.assert` to write tests that assert on values.

```eyg
let {assert, expect} = @aok

[
  {name: "addition test", test: (_) -> {
    let _ = assert.equal(3, !int_add(1, 2))
    {}
  }}
]
```

Use `aok.expect` to write tests that assert an effect is raised.

```eyg
let {assert, expect} = @aok

let greet = (name) -> {
  let time = perform Now({})
  let _ = perform StandardOut(!string_append("Hello, ", name))
  time
}

[
  {name: "greeting test", test: (_) -> {
    let time = expect.run((_) -> { greet("Bill") }, [
      expect.now((request) -> {
        let _ = assert.equal({}, request)
        123
      }),
      expect.standard_out((message) -> {
        let _ = assert.equal_string("Hello, Bill", message)
        {}
      })
    ])
    let _ = assert.equal(123, time)
    {}
  }}
]
```

Each helper on the `expect` module corresponds to an effect available when running from the CLI.
See the full [CLI effects reference](./cli_effects_reference.md).

### Exiting

`Exit` never resumes the program. Its check receives the exit status and returns
the final value of `expect.run`, rather than a reply to `perform Exit`:

```eyg
let {assert, expect} = @aok
let status = expect.run((_) -> { !never(perform Exit(7)) }, [
  expect.exit((status) -> { assert.equal(7, status) })
])
assert.equal(7, status)
```

Any expectations after the exit remain unconsumed and fail the test. The test
process itself is not terminated.

## Running test

To run tests use `run_all` or `all`, `run_all` returns the values where `all` prints out results.
Use `run_test(t)` to run a single test, it returns `Pass({})` or `Fail(reason)`.
Use `debug(tests, n)` to run the single test named `n` without catching abort.
`debug` prints the full stacktrace of the error and so is most useful for fixing tests.
