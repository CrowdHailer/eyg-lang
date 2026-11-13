//// The pinned references of a program.
////
//// Before a program runs every relative import is read and every package reference resolved.
//// The lock records which module each reference resolved to.
//// Running with the lock and a store holding those modules always loads the same code.
//// Secrets are never stored, the lock records a hash of each so a replay can check a local copy is the same.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string

pub type Lock {
  Lock(
    /// Relative imports by absolute path.
    files: Dict(String, File),
    /// `@name` references, pinned to the latest release when the program was pinned.
    packages: Dict(String, Release),
    /// `@name:version` references.
    versions: Dict(#(String, Int), String),
    /// Secrets known to the run, by name, as the hex SHA-256 of their value.
    secrets: Dict(String, String),
  )
}

/// An imported file, the CID of its source text and of the content addressed module.
pub type File {
  File(source: String, module: String)
}

pub type Release {
  Release(version: Int, module: String)
}

pub fn empty() -> Lock {
  Lock(
    files: dict.new(),
    packages: dict.new(),
    versions: dict.new(),
    secrets: dict.new(),
  )
}

pub fn add_file(lock: Lock, path: String, file: File) -> Lock {
  Lock(..lock, files: dict.insert(lock.files, path, file))
}

pub fn add_package(lock: Lock, package: String, release: Release) -> Lock {
  Lock(..lock, packages: dict.insert(lock.packages, package, release))
}

pub fn add_version(
  lock: Lock,
  package: String,
  version: Int,
  module: String,
) -> Lock {
  Lock(
    ..lock,
    versions: dict.insert(lock.versions, #(package, version), module),
  )
}

pub fn add_secret(lock: Lock, name: String, digest: String) -> Lock {
  Lock(..lock, secrets: dict.insert(lock.secrets, name, digest))
}

/// Combine two locks, i.e. from runs in the same session.
pub fn merge(lock: Lock, other: Lock) -> Lock {
  Lock(
    files: dict.merge(lock.files, other.files),
    packages: dict.merge(lock.packages, other.packages),
    versions: dict.merge(lock.versions, other.versions),
    secrets: dict.merge(lock.secrets, other.secrets),
  )
}

/// Every stored block the lock refers to.
pub fn references(lock: Lock) -> List(String) {
  let files =
    dict.values(lock.files)
    |> list.flat_map(fn(file) { [file.source, file.module] })
  let packages = dict.values(lock.packages) |> list.map(fn(r) { r.module })
  let versions = dict.values(lock.versions)
  list.flatten([files, packages, versions])
  |> list.unique
}

pub fn encode(lock: Lock) -> json.Json {
  let Lock(files:, packages:, versions:, secrets:) = lock
  json.object([
    #(
      "files",
      sorted(files)
        |> list.map(fn(entry) {
          let #(path, File(source:, module:)) = entry
          #(
            path,
            json.object([
              #("source", json.string(source)),
              #("module", json.string(module)),
            ]),
          )
        })
        |> json.object,
    ),
    #(
      "packages",
      sorted(packages)
        |> list.map(fn(entry) {
          let #(name, Release(version:, module:)) = entry
          #(
            name,
            json.object([
              #("version", json.int(version)),
              #("module", json.string(module)),
            ]),
          )
        })
        |> json.object,
    ),
    #(
      "versions",
      dict.to_list(versions)
        |> list.sort(fn(a, b) { string.compare(key(a.0), key(b.0)) })
        |> json.array(fn(entry) {
          let #(#(package, version), module) = entry
          json.object([
            #("package", json.string(package)),
            #("version", json.int(version)),
            #("module", json.string(module)),
          ])
        }),
    ),
    #(
      "secrets",
      sorted(secrets)
        |> list.map(fn(entry) { #(entry.0, json.string(entry.1)) })
        |> json.object,
    ),
  ])
}

fn key(reference: #(String, Int)) {
  reference.0 <> ":" <> string.pad_start(int.to_string(reference.1), 10, "0")
}

fn sorted(entries: Dict(String, a)) -> List(#(String, a)) {
  dict.to_list(entries)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

pub fn decoder() -> decode.Decoder(Lock) {
  use files <- decode.optional_field(
    "files",
    dict.new(),
    decode.dict(decode.string, {
      use source <- decode.field("source", decode.string)
      use module <- decode.field("module", decode.string)
      decode.success(File(source:, module:))
    }),
  )
  use packages <- decode.optional_field(
    "packages",
    dict.new(),
    decode.dict(decode.string, {
      use version <- decode.field("version", decode.int)
      use module <- decode.field("module", decode.string)
      decode.success(Release(version:, module:))
    }),
  )
  use versions <- decode.optional_field(
    "versions",
    [],
    decode.list({
      use package <- decode.field("package", decode.string)
      use version <- decode.field("version", decode.int)
      use module <- decode.field("module", decode.string)
      decode.success(#(#(package, version), module))
    }),
  )
  use secrets <- decode.optional_field(
    "secrets",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )
  decode.success(Lock(
    files:,
    packages:,
    versions: dict.from_list(versions),
    secrets:,
  ))
}
