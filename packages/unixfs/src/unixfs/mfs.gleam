//// Mutable operations on a UnixFS tree.

import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/option.{type Option, None, Some}
import multiformats/cid/v1
import multiformats/hashes
import simplifile.{type FileError}
import unixfs

pub type Entry {
  File(contents: BitArray)
  Directory(links: List(unixfs.Link))
}

/// `size` is the cumulative encoded DAG size used by UnixFS links, including
/// the stored node itself.
pub type Stored {
  Stored(cid: v1.Cid, size: Int)
}

/// Compute an entry's content identifier and cumulative encoded DAG size.
pub fn identify(entry: Entry) -> Stored {
  let #(codec, bytes, children_size) = case entry {
    File(contents) -> #(unixfs.raw_code, contents, 0)
    Directory(links) -> {
      let assert Ok(bytes) = unixfs.encode_directory(links)
      let size = list.fold(links, 0, fn(size, link) { size + link.size })
      #(unixfs.dag_pb_code, bytes, size)
    }
  }
  let digest = crypto.hash(crypto.Sha256, bytes)
  let cid = v1.Cid(codec, hashes.Multihash(hashes.Sha256, digest))
  Stored(cid, bit_array.byte_size(bytes) + children_size)
}

pub type Effect(t) {
  Put(Entry, resume: fn(Result(Stored, FileError)) -> Effect(t))
  Get(cid: v1.Cid, resume: fn(Result(Entry, FileError)) -> Effect(t))
  Done(Result(t, FileError))
}

fn then(effect: Effect(a), next: fn(a) -> Effect(b)) -> Effect(b) {
  case effect {
    Done(Ok(value)) -> next(value)
    Done(Error(error)) -> Done(Error(error))
    Get(cid, resume) -> Get(cid, fn(value) { then(resume(value), next) })
    Put(entry, resume) -> Put(entry, fn(value) { then(resume(value), next) })
  }
}

/// Replace a file, or create it if only the final path component is missing.
/// Missing parents return Enoent, directories cannot be overwritten.
pub fn write(
  root: Option(Entry),
  path: List(String),
  contents: BitArray,
) -> Effect(Entry) {
  update(root, path, Reject, fn(entry) {
    case entry {
      Some(Directory(_)) -> Error(simplifile.Eisdir)
      Some(File(_)) | None -> Ok(File(contents))
    }
  })
}

/// Append bytes to a file, creating it if only the final component is missing.
pub fn append(
  root: Option(Entry),
  path: List(String),
  contents: BitArray,
) -> Effect(Entry) {
  update(root, path, Reject, fn(entry) {
    case entry {
      Some(Directory(_)) -> Error(simplifile.Eisdir)
      Some(File(existing)) -> Ok(File(<<existing:bits, contents:bits>>))
      None -> Ok(File(contents))
    }
  })
}

/// Create an empty directory. Parents must exist.
pub fn make_directory(
  root: Option(Entry),
  path: List(String),
) -> Effect(Entry) {
  update(root, path, Reject, fn(entry) {
    case entry {
      Some(_) -> Error(simplifile.Eexist)
      None -> Ok(Directory([]))
    }
  })
}

/// Ensure a directory exists, creating missing parents.
/// Existing directories and their contents are preserved.
pub fn make_directory_all(
  root: Option(Entry),
  path: List(String),
) -> Effect(Entry) {
  update(root, path, CreateDirectories, fn(entry) {
    case entry {
      None -> Ok(Directory([]))
      Some(Directory(links)) -> Ok(Directory(links))
      Some(File(_)) -> Error(simplifile.Enotdir)
    }
  })
}

/// Delete a file, or a directory and everything in it.
/// The root cannot be deleted.
pub fn delete(root: Option(Entry), path: List(String)) -> Effect(Entry) {
  case list.reverse(path) {
    [] -> Done(Error(simplifile.Ebusy))
    [name, ..parent] ->
      update(root, list.reverse(parent), Reject, fn(entry) {
        case entry {
          Some(Directory(links)) ->
            case link_by_name(links, name) {
              Ok(_) ->
                Ok(
                  Directory(list.filter(links, fn(link) { link.name != name })),
                )
              Error(Nil) -> Error(simplifile.Enoent)
            }
          Some(File(_)) -> Error(simplifile.Enotdir)
          None -> Error(simplifile.Enoent)
        }
      })
  }
}

/// Read the contents of a directory.
pub fn read_directory(
  root: v1.Cid,
  path: List(String),
) -> Effect(List(unixfs.Link)) {
  use entry <- then(Get(root, Done))
  case entry, path {
    Directory(links), [] -> Done(Ok(links))
    File(_), _ -> Done(Error(simplifile.Enotdir))
    Directory(links), [name, ..rest] ->
      case link_by_name(links, name) {
        Ok(link) -> read_directory(link.cid, rest)
        Error(_) -> Done(Error(simplifile.Enoent))
      }
  }
}

/// Read the complete contents of a file. Reading a directory returns Eisdir.
pub fn read(root: v1.Cid, path: List(String)) -> Effect(BitArray) {
  use entry <- then(Get(root, Done))
  case entry, path {
    File(contents), [] -> Done(Ok(contents))
    Directory(_), [] -> Done(Error(simplifile.Eisdir))
    File(_), [_, ..] -> Done(Error(simplifile.Enotdir))
    Directory(links), [name, ..rest] ->
      case link_by_name(links, name) {
        Ok(link) -> read(link.cid, rest)
        Error(_) -> Done(Error(simplifile.Enoent))
      }
  }
}

type MissingParents {
  Reject
  CreateDirectories
}

// None represents an absent entry, not a failed store lookup.
fn update(
  root: Option(Entry),
  path: List(String),
  missing_parents: MissingParents,
  change: fn(Option(Entry)) -> Result(Entry, FileError),
) -> Effect(Entry) {
  case root, path {
    _, [] -> Done(change(root))
    None, [_, ..] ->
      case missing_parents {
        Reject -> Done(Error(simplifile.Enoent))
        CreateDirectories ->
          update(Some(Directory([])), path, missing_parents, change)
      }
    Some(File(_)), [_, ..] -> Done(Error(simplifile.Enotdir))
    Some(Directory(links)), [name, ..rest] -> {
      let links =
        upsert_link(links, name, fn(link) {
          let child = case link {
            Some(link) -> {
              use entry <- then(Get(link.cid, Done))
              update(Some(entry), rest, missing_parents, change)
            }
            None -> update(None, rest, missing_parents, change)
          }
          use child <- then(child)
          use stored <- then(Put(child, Done))
          Done(Ok(unixfs.Link(stored.cid, name, stored.size)))
        })
      use links <- then(links)
      Done(Ok(Directory(links)))
    }
  }
}

fn upsert_link(
  links: List(unixfs.Link),
  name: String,
  change: fn(Option(unixfs.Link)) -> Effect(unixfs.Link),
) -> Effect(List(unixfs.Link)) {
  case links {
    [] -> {
      use link <- then(change(None))
      Done(Ok([link]))
    }
    [link, ..rest] if link.name == name -> {
      use link <- then(change(Some(link)))
      Done(Ok([link, ..rest]))
    }
    [link, ..rest] -> {
      use rest <- then(upsert_link(rest, name, change))
      Done(Ok([link, ..rest]))
    }
  }
}

fn link_by_name(
  links: List(unixfs.Link),
  name: String,
) -> Result(unixfs.Link, Nil) {
  list.find(links, fn(link) { link.name == name })
}
