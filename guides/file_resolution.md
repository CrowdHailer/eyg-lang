---
name: File resolution
description: How EYG resolves imports and filesystem paths in CLI programs.
---

# File Resolution

EYG uses two different directories when a program runs in the CLI.

**Source Directory** is the directory containing the file where the current
source expression was written.

**Current Working Directory (CWD)** is the directory where the `eyg` process was started.

## Relative paths

All filesystem effects and import statements with relative paths are resolved from the source directory.
The relative path is resolved from the source directory of the file containing the import or effect expression.

```eyg
// app/entry.eyg
let helper = import "helper.eyg"
let also_helper = import "./helper.eyg"
let nested = import "lib/nested.eyg"
```

All three paths are resolved from `app/`, no matter where the user runs
`eyg` from.

This behaviour is so imports and effects have matching behaviour.

**Only modules on the file system have a source directory, all imports and relative file system operations fail for published modules.**

## Current working directory.

For many applications, CLI tools in particular, relative paths should be resolved relative to the invocation directory.
Use the `CWD` effect to find the current working directory

```eyg
let cwd = match perform CWD({}) {
  Ok(cwd) -> { cwd }
  Error(reason) -> { !never(perform Abort(reason)) }
}
let path = !string_append(cwd, "/config.json")

match perform ReadFile({path, offset: 0, limit: 1000000}) {
  Ok(bytes) -> { bytes }
  Error(reason) -> { !never(perform Abort(reason)) }
}
```

This reads `config.json` relative to the current working directory.

## Rational

Auto resolution of relative imports is a hidden side-effect.
It relies on the location of the caller in a file system without that being reflected in the type system.

EYG always favours explicitness.
Making the `CWD` effect explicit forces a program to disclose it if relies on the concept of a location in the filesystem.
It is possible to systems to expose filesystem effects without a `CWD` effect.

Currently imports are resolved relative to source directory.
This behaviour is chosen because:

1. Relative references cannot be shared or published.
2. This matches expected behaviour locally.

A way to read source relative to the current project is needed for the usecase of an `entry.eyg` file publishing code.
As the CWD is now explicit and `entry.eyg` files are not expected to be shared then relative paths can be used for this source relative use case.

### Future directions

It's possible that even reading the source directory will become an explicit effect. i.e.

```
let source = perform Source({})
{
  script: (_args) -> {
    let cwd = perform CWD({})
    0
  }
}
```

At the top level `CWD` is unavailabe and in the script function `Source` is unavailable.
This might be better but doesn't increase expressive power at all.
It also doesn't match perfectly with imports because imports can be used in the script function but are still source relative.

Even further this makes `import` look like a compile time construct.
Maybe a specific `load` primitive allows import like behaviour, but returning the string.

The final state might be a replacement of import with load and eval.
Reimplementing a type safe eval is on the roadmap but currently a little way out.