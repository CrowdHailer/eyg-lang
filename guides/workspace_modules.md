# Workspace modules

During development it is useful to reference an unpublished module that might be mutated as part of the current development.

The EYG IR has two inbuilt references kinds.

1. `Reference` Modules identified just by hash
2. `Release` Published modules identified by a package name an version with a hash as a checksum.

A `Reference` is immutable and a `Release` has been published to the EYG Hub.
Neither work for an in development module.

## Unpublished releases
Also called `relative references` or `path references`

An unpublished release addresses a module within your workspace.
Workspaces are normally the files on your computer so the address is normally a filepath.

*Workspaces don't have to be filesystems and addresses don't have to be paths. For example, using EYG in a spreadsheet and referencing cells*

## IR Representation

To publish a EYG module it must contain only valid references and releases.
Unpublished releases are represented as structurally valid releases but without a valid version or hash

```gleam
let relative = Release(package: "./index.eyg.json", version: 0, identifier: dag_json.vacant_cid)
let relative = Release(package: "/lib/http.eyg.json", version: 0, identifier: dag_json.vacant_cid)
```

These releases are unpublishable for all the following reasons:
- the name contains `.` and `/`
- the version is less than 1
- the indentifier doesn't match the module content.

When implementing EYG is a workspace it's standard to check for a version 0 to recognise a workspace module.

## Text Representation

Releases are identified with `@` and references with `#`.
The early version of unpublished packages used literals starting with `./` or `/`.
This was unworkable as the format of the address is defined by the workspace.
For example a file name might contain whitespace and most likely does contain `.` which can be confused with field selection.

Unpublished releases are identified by the `import` keyword.

```
let relative = import "./index.eyg.json"
let absoulute = import "/lib/http.eyg.json"
```
Addresses must be string literals, there is no support for dynamic import
