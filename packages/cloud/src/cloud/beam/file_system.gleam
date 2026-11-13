//// Operations on a session's UnixFS root using the actor's shared block store.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import simplifile.{type FileError}
import touch_grass/file_system/read_directory
import unixfs/mfs

/// This is only useful for passing through execution state.
/// TODO remove this once blocks are stored out of process.
pub type State {
  State(root: v1.Cid, blocks: Dict(v1.Cid, mfs.Entry))
}

pub fn new(blocks: Dict(v1.Cid, mfs.Entry)) -> State {
  let #(root, blocks) = put(blocks, mfs.Directory([]))
  State(root.cid, blocks)
}

fn put(blocks, entry) {
  let stored = mfs.identify(entry)
  #(stored, dict.insert(blocks, stored.cid, entry))
}

fn run(effect: mfs.Effect(a), blocks) {
  case effect {
    mfs.Done(value) -> #(value, blocks)
    mfs.Get(cid, resume) -> {
      let entry =
        dict.get(blocks, cid) |> result.replace_error(simplifile.Enoent)
      run(resume(entry), blocks)
    }
    mfs.Put(entry, resume) -> {
      let #(stored, blocks) = put(blocks, entry)
      run(resume(Ok(stored)), blocks)
    }
  }
}

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

fn change(fs: State, path: String, operation) -> #(Result(Nil, String), State) {
  let updated = {
    use parts <- result.try(path_parts(path))
    let assert Ok(root) = dict.get(fs.blocks, fs.root)
    let #(root, blocks) = run(operation(Some(root), parts), fs.blocks)
    use root <- result.map(root)
    let #(stored, blocks) = put(blocks, root)
    State(stored.cid, blocks)
  }
  case updated {
    Ok(fs) -> #(Ok(Nil), fs)
    Error(reason) -> #(Error(simplifile.describe_error(reason)), fs)
  }
}

pub fn write(fs: State, path: String, contents: BitArray) {
  change(fs, path, fn(root, parts) { mfs.write(root, parts, contents) })
}

pub fn append(fs: State, path: String, contents: BitArray) {
  change(fs, path, fn(root, parts) { mfs.append(root, parts, contents) })
}

pub fn make_directory(fs: State, path: String) {
  change(fs, path, mfs.make_directory_all)
}

pub fn delete(fs: State, path: String) {
  change(fs, path, mfs.delete)
}

pub fn read(
  fs: State,
  path: String,
  offset: Int,
  limit: Int,
) -> Result(BitArray, String) {
  let contents = {
    use parts <- result.try(path_parts(path))
    case offset < 0 || limit < 0 {
      True -> Error(simplifile.Einval)
      False -> {
        use bytes <- result.try(run(mfs.read(fs.root, parts), fs.blocks).0)
        let size = bit_array.byte_size(bytes)
        case offset >= size {
          True -> Ok(<<>>)
          False ->
            bit_array.slice(bytes, offset, int.min(limit, size - offset))
            |> result.replace_error(simplifile.Einval)
        }
      }
    }
  }
  result.map_error(contents, simplifile.describe_error)
}

pub fn read_directory(fs: State, path: String) -> read_directory.Output {
  let entries = {
    use parts <- result.try(path_parts(path))
    use links <- result.try(
      run(mfs.read_directory(fs.root, parts), fs.blocks).0,
    )
    links
    |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
    |> list.try_map(fn(link) {
      use entry <- result.map(
        dict.get(fs.blocks, link.cid)
        |> result.replace_error(simplifile.Enoent),
      )
      let metadata = case entry {
        mfs.File(contents) -> read_directory.File(bit_array.byte_size(contents))
        mfs.Directory(_) -> read_directory.Directory
      }
      #(link.name, metadata)
    })
  }
  result.map_error(entries, simplifile.describe_error)
}
