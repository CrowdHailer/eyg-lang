# Plinthx

Bindings to platform APIs that the published version of
[plinth](https://hex.pm/packages/plinth) does not have, used by packages in this
repository. Bindings follow plinth's conventions so they can be moved upstream.

Follow the [Plinth README at ba246f2](https://github.com/CrowdHailer/plinth/blob/ba246f26ff05ef933a5e1664def8d59ffbde317d/README.md),
the upstream HEAD checked on 2026-10-04:

- Place bindings by the API's defining specification: Web APIs in
  `plinthx/browser`, ECMAScript in `plinthx/javascript`, Node APIs in
  `plinthx/node`, Bun APIs in `plinthx/bun`. Node APIs that Bun also
  implements are in `plinthx/node`.
- Fetch a global with `get()` (or `get_name()` for multiple globals), through
  `globalThis`, checking its native type. Return `Result(object, Nil)` when
  lookup cannot throw, or `Result(object, String)` when it can.
- Return the native object and pass the receiver first to methods. Preserve
  native mutation and lifetime semantics.
- Return `Result` for fallible calls and missing optional values. Construct
  errors with `Result$Error`; convert thrown values with `String(error)`.
- Avoid legacy named/indexed window lookup and higher-level abstractions.

Add only the bindings a package in this repository uses. They do not change the
existing bindings inside third-party dependencies.
