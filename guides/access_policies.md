---
name: Effect access policies
description: Add policies for calling side effects with the overlay access package.
---

Use `overlay.access` to apply policies to CLI side effects.
This allows you to run untrusted source with fine grained permissions.

## Getting started

Use the published package. (currently unpublished)

```eyg
let access = @overlay.access
```

Inside this repository, use the prereleased package.

```eyg
let access = import "../eyg_packages/overlay/index.eyg".access
```

## Examples

Blanket block all side-effects.

```eyg
let result = access.apply(access.deny_all, (_) -> {
  perform ReadDirectory(".")
})
// Error("read_directory denied by policy")
```

Block only the `DeleteFile` effect.

```eyg
let policy = {
  delete_file: access.deny("deletion is disallowed")
  ..access.allow_all
}

let result = access.apply(policy, (_) -> {
  perform ReadDirectory(".")
})
// Ok([some files])
```

Sophisticated white list of allowed effects.

```eyg
let access = import "../eyg_packages/overlay/index.eyg".access

let policy = {
  fetch: access.fetch.allow_get_hosts(["api.example.com"]),
  read_file: access.all([
    access.read_file.allow_under(["fixtures"]),
    access.read_file.max_bytes(1000000)
  ]),
  read_directory: access.read_directory.allow_under(["fixtures"]),
  ..access.deny_all
}
```

## Managed effects

The following effects can be managed.

- `Fetch`
- `ReadFile`
- `ReadDirectory`
- `WriteFile`
- `AppendFile`
- `DeleteFile`

Non-result effects such as `Print`, `Now`, `Random`, and `Sleep` are not managed by this package.

This library introduces no new control flow, denied effects will be handled in the same way by the executing function as any other failure.

## Write your own policies

Each policy field returns a decision value.

```eyg
Allow({})      // perform the original host effect
Mock(value)    // resume as Ok(value)
Deny(reason)   // resume as Error(reason)
```

Denied operations resume as the effect's normal `Error(reason)` value.
Mocked operations resume as `Ok(value)`.

```
let only_localhost = (request) -> {
  match !equal(request.host, "localhost") {
    True -> Allow({})
    False -> Deny("only localhost can be accessed.")
  }
}
let policy = {fetch: only_localhost, ..access.deny_all}
```

## Policy constants

`allow_all` allows every intercepted effect. It is useful when you want to deny
or mock only one field.

```eyg
let policy = {
  read_file: access.deny("file reads are disabled here"),
  ..access.allow_all
}
```

`deny_all` denies every intercepted effect. This is the safer starting point
for scripts that opt in to a small set of capabilities.

```eyg
let policy = {
  read_file: access.read_file.allow_exact(["fixtures/input.txt"]),
  ..access.deny_all
}
```

The lower value remains a normal result:

```eyg
access.apply(policy, (_) -> {
  match perform ReadFile({path: "secret.txt", offset: 0, limit: 1000}) {
    Ok(bytes) -> { bytes }
    Error(reason) -> { !string_to_binary(reason) }
  }
})
```

## Fetch helpers

Use the fetch helpers when the policy is about hosts or origins.

```eyg
let only_api_gets = access.fetch.allow_get_hosts(["api.example.com"])
let only_origins = access.fetch.allow_origins([
  {scheme: HTTPS({}), host: "api.example.com", port: None({})}
])
let block_metadata = access.fetch.deny_hosts(["metadata.google.internal"])
```

`access.fetch.mock_response(response)` and `access.fetch.mock_json(status,
body)` are useful for deterministic tests.

## File helpers

Path helpers normalize `.` and `..` lexically before checking roots or exact
paths. They reject paths that escape above the starting root and reject absolute
paths. Symbolic links are still resolved by the runtime, not by the package.

```eyg
let read_policy = access.all([
  access.read_file.allow_under(["data"]),
  access.read_file.max_bytes(65536)
])

let write_policy = access.all([
  access.write_file.allow_under(["workspace"]),
  access.write_file.max_bytes(1000000)
])
```

For common filesystem policies, build fields together:

```eyg
let read_only = access.file.allow_read_under(["fixtures"])
let workspace = access.file.allow_under(["workspace"])

let policy = {
  read_file: read_only.read_file,
  read_directory: read_only.read_directory,
  write_file: workspace.write_file,
  append_file: workspace.append_file,
  delete_file: workspace.delete_file,
  ..access.deny_all
}
```

Mock helpers are available for dry runs and tests:

```eyg
let dry_run = {
  write_file: access.write_file.mock_success,
  append_file: access.append_file.mock_success,
  delete_file: access.delete_file.mock_success,
  ..access.deny_all
}
```

