# Compiled effect runtime

Gleam implements the persistent continuation machine used by the JavaScript
compiler. Generated code constructs calls, binds, delimiters and resumptions;
native JavaScript functions and values cross a small platform binding.

From this package:

```sh
gleam test
gleam run -m generate
gleam run -m generate -- --check
```

Generation uses Bun 1.3.14 to bundle the compiled Gleam library into the
compiler's runtime.gleam constant. Commit that generated input with its source.
The check fails if the bundle is stale. No separate runtime installation is
needed by the emitted JavaScript.

The [handler guide](../../guides/deep_effect_handlers.md) describes semantics.
Tests check deep scope, independent resumptions, host-callable partial functions,
100,000 tail calls and constant continuation/capture sizes across 10,000 updates.
