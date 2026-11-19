//// Mutable operations on a UnixFS tree.

import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
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
  let #(codec, children_size) = case entry {
    File(_) -> #(unixfs.raw_code, 0)
    Directory(links) -> #(
      unixfs.dag_pb_code,
      list.fold(links, 0, fn(size, link) { size + link.size }),
    )
  }
  let bytes = encode(entry)
  let digest = crypto.hash(crypto.Sha256, bytes)
  let cid = v1.Cid(codec, hashes.Multihash(hashes.Sha256, digest))
  Stored(cid, bit_array.byte_size(bytes) + children_size)
}

/// Encode an Entry as it's bytes.
pub fn encode(entry: Entry) -> BitArray {
  case entry {
    File(contents) -> contents
    Directory(links) -> {
      let assert Ok(bytes) = unixfs.encode_directory(links)
      bytes
    }
  }
}

/// Decode a block based on the CID content type.
pub fn decode(cid: v1.Cid, block: BitArray) -> Result(Entry, Nil) {
  case cid.content_type == unixfs.raw_code {
    True -> Ok(File(block))
    False -> result.map(unixfs.decode_directory(block), Directory)
  }
}

/// Storage failures are handled by the runner; continuations receive successful
/// responses. Filesystem operation errors are ordinary return values.
pub type Effect(t) {
  Put(Entry, resume: fn(Stored) -> Effect(t))
  Get(cid: v1.Cid, resume: fn(Entry) -> Effect(t))
  Done(t)
}

/// Compose effectful operations. Every completed value is passed to `next`,
/// including errors when the value is a Result.
pub fn then(effect: Effect(a), next: fn(a) -> Effect(b)) -> Effect(b) {
  case effect {
    Done(value) -> next(value)
    Get(cid, resume) -> Get(cid, fn(value) { then(resume(value), next) })
    Put(entry, resume) -> Put(entry, fn(value) { then(resume(value), next) })
  }
}

/// Continue on success, or return the error without running `next`.
pub fn try(
  value: Result(a, e),
  next: fn(a) -> Effect(Result(b, e)),
) -> Effect(Result(b, e)) {
  case value {
    Ok(value) -> next(value)
    Error(error) -> Done(Error(error))
  }
}

pub fn each(items: List(a), f: fn(a) -> Effect(b)) -> Effect(List(b)) {
  case items {
    [] -> Done([])
    [item, ..rest] -> {
      use first <- then(f(item))
      use rest <- then(each(rest, f))
      Done([first, ..rest])
    }
  }
}

fn do_try_each(
  items: List(a),
  f: fn(a) -> Effect(Result(b, c)),
  acc: List(b),
) -> Effect(Result(List(b), c)) {
  case items {
    [] -> Done(Ok(list.reverse(acc)))
    [item, ..rest] -> {
      use item <- then(f(item))
      case item {
        Ok(item) -> do_try_each(rest, f, [item, ..acc])
        Error(reason) -> Done(Error(reason))
      }
    }
  }
}

/// Replace a file, or create it if only the final path component is missing.
/// Missing parents return Enoent, directories cannot be overwritten.
pub fn write(
  root: Option(Entry),
  path: List(String),
  contents: BitArray,
) -> Effect(Result(Entry, FileError)) {
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
) -> Effect(Result(Entry, FileError)) {
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
) -> Effect(Result(Entry, FileError)) {
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
) -> Effect(Result(Entry, FileError)) {
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
pub fn delete(
  root: Option(Entry),
  path: List(String),
) -> Effect(Result(Entry, FileError)) {
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
) -> Effect(Result(List(unixfs.Link), FileError)) {
  use entry <- Get(root)
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
pub fn read(
  root: v1.Cid,
  path: List(String),
) -> Effect(Result(BitArray, FileError)) {
  use entry <- Get(root)
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
) -> Effect(Result(Entry, FileError)) {
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
              use entry <- Get(link.cid)
              update(Some(entry), rest, missing_parents, change)
            }
            None -> update(None, rest, missing_parents, change)
          }
          use child <- then(child)
          use child <- try(child)
          use stored <- Put(child)
          Done(Ok(unixfs.Link(stored.cid, name, stored.size)))
        })
      use links <- then(links)
      use links <- try(links)
      Done(Ok(Directory(links)))
    }
  }
}

fn upsert_link(
  links: List(unixfs.Link),
  name: String,
  change: fn(Option(unixfs.Link)) -> Effect(Result(unixfs.Link, FileError)),
) -> Effect(Result(List(unixfs.Link), FileError)) {
  case links {
    [] -> {
      use link <- then(change(None))
      use link <- try(link)
      Done(Ok([link]))
    }
    [link, ..rest] if link.name == name -> {
      use link <- then(change(Some(link)))
      use link <- try(link)
      Done(Ok([link, ..rest]))
    }
    [link, ..rest] -> {
      use rest <- then(upsert_link(rest, name, change))
      use rest <- try(rest)
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

/// List the paths of all files that differ between old and new tree.
pub fn diff(old: v1.Cid, new: v1.Cid) -> Effect(List(List(String))) {
  case old == new {
    True -> Done([])
    False -> {
      use old <- Get(old)
      use new <- Get(new)
      case old, new {
        Directory(old), Directory(new) -> {
          let names =
            list.append(old, new)
            |> list.map(fn(link) { link.name })
            |> list.unique
          use paths <- then(
            each(names, fn(name) {
              use paths <- then(
                case link_by_name(old, name), link_by_name(new, name) {
                  Ok(old), Ok(new) -> diff(old.cid, new.cid)
                  Ok(only), Error(Nil) | Error(Nil), Ok(only) -> files(only.cid)
                  Error(Nil), Error(Nil) -> Done([])
                },
              )
              Done(list.map(paths, fn(path) { [name, ..path] }))
            }),
          )
          Done(list.flatten(paths))
        }
        File(_), File(_) -> Done([[]])
        _, _ -> {
          use old <- then(entry_files(old))
          use new <- then(entry_files(new))
          Done(list.append(old, new))
        }
      }
    }
  }
}

/// The paths of every file in a tree.
pub fn files(root: v1.Cid) -> Effect(List(List(String))) {
  use entry <- Get(root)
  entry_files(entry)
}

fn entry_files(entry: Entry) -> Effect(List(List(String))) {
  case entry {
    File(_) -> Done([[]])
    Directory(links) -> {
      use paths <- then(
        each(links, fn(link) {
          use paths <- then(files(link.cid))
          Done(list.map(paths, fn(path) { [link.name, ..path] }))
        }),
      )
      Done(list.flatten(paths))
    }
  }
}

/// 3-way merge only the directories.
/// The Gliff package already exists for text merging.
pub fn merge(
  base: Option(Stored),
  ours: Option(Stored),
  theirs: Option(Stored),
) -> Effect(Result(Option(Stored), Nil)) {
  case base, ours, theirs {
    _base, ours, theirs if ours == theirs -> Done(Ok(ours))
    base, ours, theirs if theirs == base -> Done(Ok(ours))
    base, ours, theirs if ours == base -> Done(Ok(theirs))

    base, ours, theirs -> {
      use base <- then(fetch_it(base))
      use ours <- then(fetch_it(ours))
      use theirs <- then(fetch_it(theirs))
      let base = case base {
        Some(Directory(base)) -> base
        _ -> []
      }
      case ours, theirs {
        Some(Directory(ours)), Some(Directory(theirs)) -> {
          let names =
            [base, ours, theirs]
            |> list.flatten
            |> list.map(fn(link) { link.name })
            |> list.unique
          use links <- then(
            do_try_each(
              names,
              fn(name) {
                let child = fn(links) {
                  link_by_name(links, name)
                  |> result.map(fn(link: unixfs.Link) {
                    Stored(link.cid, link.size)
                  })
                  |> option.from_result
                }
                use new <- then(merge(child(base), child(ours), child(theirs)))
                use new <- try(new)

                case new {
                  Some(stored) -> [unixfs.Link(stored.cid, name, stored.size)]
                  None -> []
                }
                |> Ok
                |> Done
              },
              [],
            ),
          )
          use links <- try(links)
          let links = list.flatten(links)
          use stored <- Put(Directory(links))
          Done(Ok(Some(stored)))
        }

        _, _ -> Done(Error(Nil))
      }
    }
  }
}

fn fetch_it(stored: Option(Stored)) {
  case stored {
    Some(stored) -> {
      use entry <- Get(stored.cid)
      Done(Some(entry))
    }
    None -> Done(None)
  }
}
