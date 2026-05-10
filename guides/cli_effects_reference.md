---
title: CLI effects reference
description: reference for effects implemented by the eyg CLI .
---

EYG separates the **declaration** of an effect (in your script:
`perform Foo(...)`) from its **implementation** (provided by the runner).
The CLI in this repository ([`packages/gleam_cli`](../packages/gleam_cli/))
implements the effects below.

## File system

### `ReadFile`

Read a slice of a file at a given byte offset.

```eyg
match perform ReadFile({path: "data.txt", offset: 0, limit: 1000000}) {
  Ok(bytes) -> { !string_from_binary(bytes) }
  Error(reason) -> { !never(Abort(reason)) }
}
```

| Field | Type | Notes |
|---|---|---|
| `path` | `String` | Resolved relative to the script's directory |
| `offset` | `Int` | Byte offset to start reading from |
| `limit` | `Int` | Maximum bytes to read |

Returns `Result(Binary, String)`.

### `WriteFile`

Overwrite a file with new contents (creating it if necessary).

```eyg
perform WriteFile({path: "out.txt", contents: !string_to_binary("hello")})
```

Returns `Result({}, String)`.

### `AppendFile`

Append bytes to a file. Safe for concurrent appends.

```eyg
perform AppendFile({path: "log.txt", contents: !string_to_binary("a line\n")})
```

Returns `Result({}, String)`.

### `ReadDirectory`

List entries in a directory. Excludes `.` and `..`.

```eyg
match perform ReadDirectory(".") {
  Ok(entries) -> { entries }
  Error(reason) -> { !never(Abort(reason)) }
}
```

Returns `Result(List({name: String, type: Directory({}) | File({size: Int})}), String)`.

For a recursive walk, see
[`eyg_packages/fs/index.eyg`](../eyg_packages/fs/index.eyg)'s `list` and
`list_files` helpers.

## I/O

### `Print`

Write a string to stdout. No newline is added.

```eyg
perform Print("hello\n")
```

Returns `{}`.

## Network

### `Fetch`

Make an HTTP request.

```eyg
let request = {
  method: GET({}),
  scheme: HTTP({}),
  host: "example.com",
  port: None({}),
  path: "",
  query: None({}),
  headers: [],
  body: !string_to_binary(""),
}
match perform Fetch(request) {
  Ok({status, headers, body}) -> { status }
  Error(reason) -> { !never(Abort(reason)) }
}
```

Returns `Result({status: Int, headers: List(...), body: Binary}, String)`.

## Parsing

### `DecodeJSON`

Parse a JSON binary into a flat list of `{term, depth}` events.

```eyg
match perform DecodeJSON(!string_to_binary("{\"x\": 1}")) {
  Ok(events) -> { events }
  Error(reason) -> { !never(Abort(reason)) }
}
```

Each event's `term` is one of: `True | False | Null | Integer i | String s | Number {…} | Array | Object | Field name`.

## Authenticated services

Each of these performs a [spotless](https://hex.pm/packages/spotless) OAuth
flow the first time it's used and caches the token. The lift / lower shape
matches `Fetch`, but the request is rewritten to point at the service's API
host with the bearer token attached.

| Effect | Host |
|---|---|
| `GitHub` | `api.github.com` |
| `Netlify` | `api.netlify.com` |
| `DNSimple` | `api.dnsimple.com` |
| `Vimeo` | `api.vimeo.com` |

```eyg
let request = {
  method: GET({}),
  scheme: HTTPS({}),
  host: "api.github.com",
  port: None({}),
  path: "/user",
  query: None({}),
  headers: [],
  body: !string_to_binary(""),
}
perform GitHub(request)
```
