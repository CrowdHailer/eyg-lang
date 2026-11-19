//// File system operations for the paths written in programs.
//// Each takes the root of a file system and returns the effects needed on its blocks.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import simplifile.{type FileError}
import touch_grass/file_system/read_directory
import unixfs
import unixfs/mfs

// Relative and absolute paths resolve from the virtual root. Parent components
// at the root stay at the root, never reaching the host filesystem.
// TODO move this to unixfs
fn path_parts(path: String) -> Result(List(String), FileError) {
  case path == "" || string.contains(path, "\u{0}") {
    True -> Error(simplifile.Einval)
    False ->
      string.split(path, "/")
      |> list.fold([], fn(parts, part) {
        case part, parts {
          "", _ | ".", _ -> parts
          "..", [] -> []
          "..", [_, ..rest] -> rest
          _, _ -> [part, ..parts]
        }
      })
      |> list.reverse
      |> Ok
  }
}

/// Use the same canonical path for policy checks and filesystem operations.
pub fn resolve_path(path: String) -> Result(String, String) {
  path_parts(path)
  |> result.map(fn(parts) { "/" <> string.join(parts, "/") })
  |> result.map_error(simplifile.describe_error)
}

/// The root of a file system with no files.
pub fn empty() -> mfs.Effect(v1.Cid) {
  use stored <- mfs.Put(mfs.Directory([]))
  mfs.Done(stored.cid)
}

fn at(
  path: String,
  then: fn(List(String)) -> mfs.Effect(Result(a, FileError)),
) -> mfs.Effect(Result(a, FileError)) {
  case path_parts(path) {
    Ok(parts) -> then(parts)
    Error(reason) -> mfs.Done(Error(reason))
  }
}

// Every change returns the root of the changed file system.
fn change(
  root: v1.Cid,
  path: String,
  operation,
) -> mfs.Effect(Result(v1.Cid, FileError)) {
  use parts <- at(path)
  use entry <- mfs.Get(root)
  use entry <- mfs.then(operation(Some(entry), parts))
  use entry <- mfs.try(entry)
  use stored <- mfs.Put(entry)
  mfs.Done(Ok(stored.cid))
}

pub fn write(root: v1.Cid, path: String, contents: BitArray) {
  change(root, path, fn(root, parts) { mfs.write(root, parts, contents) })
}

pub fn append(root: v1.Cid, path: String, contents: BitArray) {
  change(root, path, fn(root, parts) { mfs.append(root, parts, contents) })
}

pub fn make_directory(root: v1.Cid, path: String) {
  change(root, path, mfs.make_directory_all)
}

pub fn delete(root: v1.Cid, path: String) {
  change(root, path, mfs.delete)
}

pub fn read_range(
  root: v1.Cid,
  path: String,
  offset: Int,
  limit: Int,
) -> mfs.Effect(Result(BitArray, FileError)) {
  use bytes <- mfs.then(read(root, path))
  use bytes <- mfs.try(bytes)
  let size = bit_array.byte_size(bytes)
  mfs.Done(case offset < 0 || limit < 0 {
    True -> Error(simplifile.Einval)
    False if offset >= size -> Ok(<<>>)
    False ->
      bit_array.slice(bytes, offset, int.min(limit, size - offset))
      |> result.replace_error(simplifile.Einval)
  })
}

/// The complete contents of a file.
pub fn read(
  root: v1.Cid,
  path: String,
) -> mfs.Effect(Result(BitArray, FileError)) {
  use parts <- at(path)
  mfs.read(root, parts)
}

/// Read the contents of a diractory in a file system at the given path.
///
/// Directory contents are not loaded from blob store.
pub fn read_directory(
  root: v1.Cid,
  path: String,
) -> mfs.Effect(Result(List(#(String, read_directory.Entry)), FileError)) {
  use parts <- at(path)
  use links <- mfs.then(mfs.read_directory(root, parts))
  use links <- mfs.try(links)
  links
  |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
  |> list.map(fn(link) {
    let metadata = case link.cid.content_type == unixfs.raw_code {
      True -> read_directory.File(link.size)
      False -> read_directory.Directory
    }
    #(link.name, metadata)
  })
  |> Ok
  |> mfs.Done
}
