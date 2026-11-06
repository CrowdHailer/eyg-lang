//// A file system as a function of a root directory CID.
////
//// Every change returns a new root and never changes existing blocks,
//// so any earlier root is still a complete, readable file system.

import cloud/store.{type Store}
import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import gleam/string
import multiformats/cid/v1.{type Cid}
import unixfs.{type Link, Link}

pub type Entry {
  Directory
  File(size: Int)
}

pub const not_found = "no such file or directory"

pub const is_a_directory = "is a directory"

pub const not_a_directory = "not a directory"

pub const corrupt = "file system block missing or invalid"

/// The root of an empty file system.
pub fn empty(store: Store) -> Cid {
  store.put(store, unixfs.dag_pb_code, unixfs.encode_directory([]))
}

/// Split a path into its segments, resolving `.` and `..`.
/// Paths are relative to the root whether or not they start with `/`.
pub fn segments(path: String) -> List(String) {
  string.split(path, "/")
  |> list.fold([], fn(acc, segment) {
    case segment, acc {
      "", _ | ".", _ -> acc
      "..", [] -> []
      "..", [_, ..rest] -> rest
      name, _ -> [name, ..acc]
    }
  })
  |> list.reverse
}

pub fn read_file(
  store: Store,
  root: Cid,
  path: String,
) -> Result(BitArray, String) {
  use cid <- try(resolve(store, root, segments(path)))
  case unixfs.is_directory(cid) {
    True -> Error(is_a_directory)
    False -> store.get(store, cid) |> result.replace_error(corrupt)
  }
}

pub fn read_directory(
  store: Store,
  root: Cid,
  path: String,
) -> Result(List(#(String, Entry)), String) {
  use cid <- try(resolve(store, root, segments(path)))
  use links <- try(load(store, cid))
  Ok(
    list.map(links, fn(link) {
      case unixfs.is_directory(link.cid) {
        True -> #(link.name, Directory)
        False -> #(link.name, File(link.size))
      }
    }),
  )
}

/// Create or replace a file. Missing parent directories are created.
pub fn write_file(
  store: Store,
  root: Cid,
  path: String,
  contents: BitArray,
) -> Result(Cid, String) {
  use existing <- update(store, root, segments(path), True)
  case existing {
    Some(link) if link.cid.content_type == unixfs.dag_pb_code ->
      Error(is_a_directory)
    _ -> Ok(Some(put_file(store, contents)))
  }
}

/// Add to the end of a file, creating it if it does not exist.
pub fn append_file(
  store: Store,
  root: Cid,
  path: String,
  contents: BitArray,
) -> Result(Cid, String) {
  use existing <- update(store, root, segments(path), True)
  case existing {
    None -> Ok(Some(put_file(store, contents)))
    Some(link) ->
      case unixfs.is_directory(link.cid) {
        True -> Error(is_a_directory)
        False -> {
          use current <- try(
            store.get(store, link.cid) |> result.replace_error(corrupt),
          )
          Ok(Some(put_file(store, bit_array.append(current, contents))))
        }
      }
  }
}

/// Remove a file. Directories are not removed.
pub fn delete_file(
  store: Store,
  root: Cid,
  path: String,
) -> Result(Cid, String) {
  use existing <- update(store, root, segments(path), False)
  case existing {
    None -> Error(not_found)
    Some(link) ->
      case unixfs.is_directory(link.cid) {
        True -> Error(is_a_directory)
        False -> Ok(None)
      }
  }
}

/// Create a directory and any missing parents.
/// Succeeds if the directory already exists.
pub fn make_directory(
  store: Store,
  root: Cid,
  path: String,
) -> Result(Cid, String) {
  case segments(path) {
    [] -> Ok(root)
    segments -> {
      use existing <- update(store, root, segments, True)
      case existing {
        None -> Ok(Some(put_directory(store, [])))
        Some(link) ->
          case unixfs.is_directory(link.cid) {
            True -> Ok(Some(#(link.cid, link.size)))
            False -> Error(not_a_directory)
          }
      }
    }
  }
}

fn put_file(store, contents) {
  #(store.put(store, unixfs.raw_code, contents), bit_array.byte_size(contents))
}

fn put_directory(store, links) {
  let block = unixfs.encode_directory(links)
  #(
    store.put(store, unixfs.dag_pb_code, block),
    unixfs.directory_size(block, links),
  )
}

fn load(store, cid) -> Result(List(Link), String) {
  case unixfs.is_directory(cid) {
    False -> Error(not_a_directory)
    True -> {
      use block <- try(store.get(store, cid) |> result.replace_error(corrupt))
      unixfs.decode_directory(block) |> result.replace_error(corrupt)
    }
  }
}

fn resolve(store, cid, segments) -> Result(Cid, String) {
  case segments {
    [] -> Ok(cid)
    [name, ..rest] -> {
      use links <- try(load(store, cid))
      case list.find(links, fn(link) { link.name == name }) {
        Ok(link) -> resolve(store, link.cid, rest)
        Error(Nil) -> Error(not_found)
      }
    }
  }
}

/// Replace the entry at `segments` with the result of `change`,
/// rebuilding every directory on the way back up to the root.
fn update(
  store: Store,
  root: Cid,
  segments: List(String),
  create_parents: Bool,
  change: fn(Option(Link)) -> Result(Option(#(Cid, Int)), String),
) -> Result(Cid, String) {
  case segments {
    [] -> Error(is_a_directory)
    _ -> {
      use #(cid, _size) <- try(do_update(
        store,
        Some(root),
        segments,
        create_parents,
        change,
      ))
      Ok(cid)
    }
  }
}

fn do_update(store, directory, segments, create_parents, change) {
  use links <- try(case directory {
    Some(cid) -> load(store, cid)
    None -> Ok([])
  })
  case segments {
    [] -> Error(is_a_directory)
    [name, ..rest] -> {
      let existing = list.find(links, fn(link) { link.name == name })
      use replacement <- try(case rest, existing {
        [], _ -> change(option.from_result(existing))
        _, Ok(link) ->
          case unixfs.is_directory(link.cid) {
            True ->
              do_update(store, Some(link.cid), rest, create_parents, change)
              |> result.map(Some)
            False -> Error(not_a_directory)
          }
        _, Error(Nil) ->
          case create_parents {
            True ->
              do_update(store, None, rest, create_parents, change)
              |> result.map(Some)
            False -> Error(not_found)
          }
      })
      let others = list.filter(links, fn(link) { link.name != name })
      let links = case replacement {
        Some(#(cid, size)) -> [Link(name:, cid:, size:), ..others]
        None -> others
      }
      Ok(put_directory(store, links))
    }
  }
}

/// Every file, as a path from the root without a leading slash, in order.
pub fn files(store: Store, root: Cid) -> List(String) {
  walk(store, root, "")
  |> list.filter_map(fn(entry) {
    case entry {
      #(path, False) -> Ok(path)
      _ -> Error(Nil)
    }
  })
}

/// Every directory, as an absolute path, starting with `/`.
pub fn directories(store: Store, root: Cid) -> List(String) {
  [
    "/",
    ..walk(store, root, "")
    |> list.filter_map(fn(entry) {
      case entry {
        #(path, True) -> Ok("/" <> path)
        _ -> Error(Nil)
      }
    })
  ]
}

fn walk(store, cid, prefix) -> List(#(String, Bool)) {
  case load(store, cid) {
    Error(_) -> []
    Ok(links) ->
      list.flat_map(links, fn(link) {
        let path = prefix <> link.name
        case unixfs.is_directory(link.cid) {
          True -> [#(path, True), ..walk(store, link.cid, path <> "/")]
          False -> [#(path, False)]
        }
      })
  }
}

/// The entries of the directory at `path`, with their CIDs.
pub fn links(
  store: Store,
  root: Cid,
  path: String,
) -> Result(List(Link), String) {
  use cid <- try(resolve(store, root, segments(path)))
  load(store, cid)
}

/// Place each link in the directory at `path`, creating it if needed.
/// Nothing is replaced: a name that is already taken is an error.
pub fn graft(
  store: Store,
  root: Cid,
  path: String,
  links: List(Link),
) -> Result(Cid, String) {
  list.try_fold(links, root, fn(root, link) {
    let target = list.append(segments(path), [link.name])
    use existing <- update(store, root, target, True)
    case existing {
      Some(_) -> Error(link.name <> " already exists in " <> path)
      None -> Ok(Some(#(link.cid, link.size)))
    }
  })
}
