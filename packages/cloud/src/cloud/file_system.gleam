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
import touch_grass/file_system as filesystem_request
import touch_grass/file_system/read_directory
import unixfs
import unixfs/mfs

// Resolve from the virtual root using the same rules as policy checks.
fn path_parts(path: String) -> Result(List(String), FileError) {
  use path <- result.map(
    filesystem_request.resolve_path(Some("/"), path)
    |> result.replace_error(simplifile.Einval),
  )
  string.split(path, "/") |> list.filter(fn(part) { part != "" })
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
