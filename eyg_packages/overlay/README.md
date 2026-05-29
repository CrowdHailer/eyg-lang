# overlay

Runtime access policies for result-returning CLI effects. The
`access` module wraps a thunk and intercepts each effect against a
policy that can `Allow`, `Mock`, or `Deny`.

See `guides/access_policies.md` for the full prose introduction. The
short version:

```eyg
let access = import "../overlay/index.eyg".access

let result = access.apply(access.deny_all, (_) -> {
  perform ReadDirectory(".")
})
// -> Error("read_directory denied by policy")
```

## What can be wrapped

The handlers intercept:

- `Fetch`
- `ReadFile`, `ReadDirectory`
- `WriteFile`, `AppendFile`, `DeleteFile`

Non-result effects (`Print`, `Now`, `Random`, `Sleep`) are not
managed. They pass through unchanged.

