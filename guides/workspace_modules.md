# Workspace modules

During development it is useful to reference an unpublished module that might be mutated as part of the current development.

The EYG IR has five reference kinds.

1. `Content` identifies an immutable module by CID.
2. `Package` identifies the latest available release of a package.
3. `Version` identifies one package version without pinning its module CID.
4. `Pinned` identifies a published `Release` by package, version, and module CID.
5. `Relative` identifies a module within the current workspace.

Content and pinned references are stable. Package and version references require
registry resolution. Relative references are resolved by the current workspace.

## Unpublished releases
Also called `relative references` or `path references`

An unpublished release addresses a module within your workspace.
Workspaces are normally the files on your computer so the address is normally a filepath.

*Workspaces don't have to be filesystems and addresses don't have to be paths. For example, using EYG in a spreadsheet and referencing cells*

## IR Representation

To publish an EYG module it must contain only content references and pinned
releases. Workspace modules use the explicit `Relative` variant.

```gleam
let relative = Relative("./index.eyg.json")
let absolute = Relative("/lib/http.eyg.json")
```

The variant itself records that the reference is workspace-relative and cannot
be published. No version or CID placeholder is involved.

## Text Representation

Packages are identified with `@`, content references with `#`, and relative
references with `import`.
The early version of unpublished packages used literals starting with `./` or `/`.
This was unworkable as the format of the address is defined by the workspace.
For example a file name might contain whitespace and most likely does contain `.` which can be confused with field selection.

Unpublished releases are identified by the `import` keyword.

```
let relative = import "./index.eyg.json"
let absoulute = import "/lib/http.eyg.json"
```
Addresses must be string literals, there is no support for dynamic import
