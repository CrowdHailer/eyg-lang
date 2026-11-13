---
name: Masking handlers and enforcing purity
description: Route effects past one enclosing handler and guard a pure function application.
---

# Masking handlers and enforcing purity

`mask E(body)` runs body({}) while skipping one enclosing E handler. Handlers
installed inside the body still work; other labels are unaffected:

```eyg
handle Ping((_, resume) -> { resume(100) }, (_) -> {
  handle Ping((_, resume) -> { resume(1) }, (_) -> {
    let outer = mask Ping((_) -> { perform Ping({}) })
    let inner = perform Ping({})
    !int_add(outer, inner)
  })
})
```

This returns 101. `let outside = mask Ping` makes the mask first-class.
Nested masks skip successive handlers, including across suspended and repeated
resumptions. A function merely returned from the body keeps no active mask.

The type is `({} -> e A) -> <E(P,Q) | e> A`. The skipped handler's request and
reply types are independent of an outer E signature in e. This scoped duplicate
label follows [Koka's masking rule](https://koka-lang.github.io/koka/doc/book.html#sec-mask).
The IR encoding is `{"0":"hm","l":"E"}`.

A function returned by an effect can run under a mask while retaining its
Abort, logging and other surrounding effects. Masking it routes any E past the
private handler; it does not constrain all its effects to be empty.

`!pure(f)` instead requires `(A ->[] B)` and guards one application at runtime.
Effects handled inside that application are allowed. An effect reaching an
outer handler or host fails with ImpureEffect. Returned functions are not
automatically guarded, and obtaining f can perform effects before the guard.

Unchecked execution enforces the same boundaries. A mask with no remaining EYG
handler to skip fails with MaskedEffect before platform dispatch. These failures
are runtime errors, rather than catchable Abort operations.

The interpreter and compiler share the positive and failure fixtures in
spec/masking.json and spec/masking_errors.json. The syntax guide, structural
editor, highlighting, AST codecs, pinning and function capture all support masks.

Try `eyg eval -c '!pure((x) -> { !int_add(x, 1) })(41)'` to obtain 42.
The interpreter and compiler mask test suites check these examples in both runtimes.

Sandbox archives now record `eyg-sandbox-3/shallow-answers/fuel-1000000`.
The loader rejects archives with a different runtime fingerprint; recreate an
older environment with the current CLI before recording a new sandbox run.
