# Create a test library for eyg programs.

The test library should be focused and powerful.
A few orthogonal concepts should provide rich feedback.
- Tests are a function and a name.
- an assertion should match on a tagged value returning the wrapped value if the tag matches and aborting with a message if not
- Helper functions should be built around the assertion. For example for assering two values are equal and asserting that a list contains a value.
- It should be possible to run a single test or a set of tests from the EYG repl.
- running a single test from the repl should be achieved by importing it as a relative reference.
- If a test fails on an assertion Then runtime debug information and it's source context must be printed.

For example if we call the test library aok
```eyg
let aok = import "./aok/index.eyg"

let test = (_) -> {
  aok.equal(1, 2)
}
```
prints
```
`1` does not equal `2`

  4 | aok.equal(1, 2)
      ^^^^^^^^^^^^^^^
```

```eyg
let aok = import "./aok/index.eyg"

let test = (_) -> {
  let value = aok.ok(Error("bad"))
}
```

prints
```
1 value was not `Ok`

  4 | let value = aok.ok(Error("bad"))
                  ^^^^^^^^^^^^^^^^^^^^
```

Create 3 DIFFERENT approaches for the implementation of the libary.
Contrast their ergonomics by writing tests for the `@standard.string` library.