---
name: Writing tests with aok
description: Write tests for EYG packages using the aok test package.
---

## Writing a test

A test consists of a record with a `name` and `test` field.
The `test` field is a function returning any value that throws abort in case of failure.

Use `aok.assert` to write tests that assert on values.

```eyg
let {assert, expect} = import "../aok/index.eyg"
```

```eyg
[
  {name: "addition",
    test: (_) -> { assert.equal(!int_add(1, 1), 2) }},
]
```

Use `aok.expect` to write tests that assert an effect is raised.

```eyg
let my_func = (name) -> {
  perform StandardOut(!string_append("Hello, ", name))
}

[
  {name: "greeting",
    test: (_) -> {
      let {lift: message} = expect.standard_out(my_func, "Bill")
      assert.equal(message, "Hello, Bill")
  }},
]
```

The record also carries `resume`, which runs the rest of the function under
test. It answers with the next `{lift, resume}` if the function performs the
effect again, and aborts if it finishes without doing so.

## Running test

To run tests use `run_all` or `all`, `run_all` returns the values where `all` prints out results.
Use `run_test(t)` to run a single test, it returns `Pass({})` or `Fail(reason)`.
Use `debug(tests, n)` to run the single test named `n` without catching abort.
`debug` prints the full stacktrace of the error and so is most useful for fixing tests.
