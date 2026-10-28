//// A file system for sessions that have one.
////
//// Programs use the same file effects as the CLI. The browser does not give
//// sessions a workspace yet, evals do, so an agent can be checked on how it
//// keeps a project and its notes.
////
//// Paths are relative to the workspace root, a leading `/` or `./` is the
//// root and a path cannot leave it.

import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string
import touch_grass as tg
import touch_grass/file_system/append_file
import touch_grass/file_system/delete_file
import touch_grass/file_system/make_directory
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
import touch_grass/interface

pub opaque type Workspace {
  Workspace(files: Dict(String, BitArray), directories: Set(String))
}

pub type Effect {
  AppendFile(append_file.Input)
  DeleteFile(path: String)
  MakeDirectory(path: String)
  ReadDirectory(path: String)
  ReadFile(read_file.Input)
  WriteFile(write_file.Input)
}

/// The file effects of a workspace, with the same types as the CLI.
pub fn effects() -> interface.Harness(Effect, meta) {
  [
    tg.append_file() |> tg.map(AppendFile),
    tg.delete_file() |> tg.map(DeleteFile),
    tg.make_directory() |> tg.map(MakeDirectory),
    tg.read_directory() |> tg.map(ReadDirectory),
    tg.read_file() |> tg.map(ReadFile),
    tg.write_file() |> tg.map(WriteFile),
  ]
}

pub fn new() -> Workspace {
  Workspace(files: dict.new(), directories: set.new())
}

/// A workspace holding the given files, invalid paths are skipped.
pub fn from_files(files: List(#(String, BitArray))) -> Workspace {
  list.fold(files, new(), fn(workspace, file) {
    let #(path, contents) = file
    case normalize(path) {
      Ok("") | Error(_) -> workspace
      Ok(path) -> {
        let directories =
          list.fold(parents(path), workspace.directories, set.insert)
        let files = dict.insert(workspace.files, path, contents)
        Workspace(files:, directories:)
      }
    }
  })
}

/// Every file and its contents, ordered by path.
pub fn files(workspace: Workspace) -> List(#(String, BitArray)) {
  dict.to_list(workspace.files)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// Perform a file effect, returning the workspace after it and the value the
/// program resumes with.
pub fn perform(
  workspace: Workspace,
  effect: Effect,
) -> #(Workspace, v.Value(a, b)) {
  case effect {
    AppendFile(append_file.Input(path:, contents:)) ->
      update(workspace, append_file.encode, {
        use path <- result.try(file_path(workspace, path))
        let existing = dict.get(workspace.files, path) |> result.unwrap(<<>>)
        let contents = bit_array.append(existing, contents)
        Ok(put(workspace, path, contents))
      })
    DeleteFile(path:) ->
      update(workspace, delete_file.encode, {
        use normal <- result.try(normalize(path))
        case dict.has_key(workspace.files, normal) {
          True ->
            Ok(
              Workspace(
                ..workspace,
                files: dict.delete(workspace.files, normal),
              ),
            )
          False -> Error("no such file: " <> path)
        }
      })
    MakeDirectory(path:) ->
      update(workspace, make_directory.encode, {
        use normal <- result.try(normalize(path))
        case
          list.any([normal, ..parents(normal)], dict.has_key(workspace.files, _))
        {
          True -> Error("a file exists at: " <> path)
          False -> {
            let directories =
              [normal, ..parents(normal)]
              |> list.filter(fn(directory) { directory != "" })
              |> list.fold(workspace.directories, set.insert)
            Ok(Workspace(..workspace, directories:))
          }
        }
      })
    ReadDirectory(path:) -> #(
      workspace,
      read_directory.encode(list_directory(workspace, path)),
    )
    ReadFile(read_file.Input(path:, offset:, limit:)) -> #(
      workspace,
      read_file.encode(read_slice(workspace, path, offset, limit)),
    )
    WriteFile(write_file.Input(path:, contents:)) ->
      update(workspace, write_file.encode, {
        use path <- result.try(file_path(workspace, path))
        Ok(put(workspace, path, contents))
      })
  }
}

fn update(workspace, encode, result) {
  case result {
    Ok(workspace) -> #(workspace, encode(Ok(Nil)))
    Error(reason) -> #(workspace, encode(Error(reason)))
  }
}

fn put(workspace: Workspace, path, contents) {
  Workspace(..workspace, files: dict.insert(workspace.files, path, contents))
}

/// A path a file can be written to, its directory must already exist.
fn file_path(workspace: Workspace, path) {
  use normal <- result.try(normalize(path))
  case normal {
    "" -> Error("not a file: " <> path)
    _ ->
      case is_directory(workspace, normal) {
        True -> Error("a directory exists at: " <> path)
        False ->
          case parents(normal) {
            [directory, ..] ->
              case is_directory(workspace, directory) {
                True -> Ok(normal)
                False -> Error("no such directory: " <> directory)
              }
            [] -> Ok(normal)
          }
      }
  }
}

fn read_slice(workspace: Workspace, path, offset, limit) {
  use normal <- result.try(normalize(path))
  case dict.get(workspace.files, normal) {
    Ok(contents) -> {
      let size = bit_array.byte_size(contents)
      case offset < 0 || limit < 0 {
        True -> Error("offset and limit must not be negative")
        False -> {
          let start = int.min(offset, size)
          let length = int.min(limit, size - start)
          let assert Ok(slice) = bit_array.slice(contents, start, length)
          Ok(slice)
        }
      }
    }
    Error(Nil) -> Error("no such file: " <> path)
  }
}

fn list_directory(workspace: Workspace, path) {
  use normal <- result.try(normalize(path))
  case is_directory(workspace, normal) {
    False -> Error("no such directory: " <> path)
    True -> {
      let files =
        dict.to_list(workspace.files)
        |> list.filter_map(fn(file) {
          let #(file_path, contents) = file
          use name <- result.map(child(normal, file_path))
          #(name, read_directory.File(bit_array.byte_size(contents)))
        })
      let directories =
        set.to_list(workspace.directories)
        |> list.filter_map(fn(directory) {
          use name <- result.map(child(normal, directory))
          #(name, read_directory.Directory)
        })
      list.append(files, directories)
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> Ok
    }
  }
}

/// The name of a path directly inside a directory.
fn child(directory, path) {
  let rest = case directory {
    "" -> Ok(path)
    _ ->
      case string.starts_with(path, directory <> "/") {
        True -> Ok(string.drop_start(path, string.length(directory) + 1))
        False -> Error(Nil)
      }
  }
  case rest {
    Ok(name) ->
      case name != "" && !string.contains(name, "/") {
        True -> Ok(name)
        False -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

fn is_directory(workspace: Workspace, path) {
  path == "" || set.contains(workspace.directories, path)
}

/// Every directory above a path, nearest first, not including the root.
fn parents(path) {
  case list.reverse(string.split(path, "/")) {
    [_name, ..above] -> do_parents(above, [])
    [] -> []
  }
}

fn do_parents(segments, acc) {
  case segments {
    [] -> list.reverse(acc)
    [_, ..rest] ->
      do_parents(rest, [string.join(list.reverse(segments), "/"), ..acc])
  }
}

fn normalize(path) {
  string.split(path, "/")
  |> list.try_fold([], fn(acc, segment) {
    case segment, acc {
      "", _ | ".", _ -> Ok(acc)
      "..", [_, ..rest] -> Ok(rest)
      "..", [] -> Error("path leaves the workspace: " <> path)
      _, _ -> Ok([segment, ..acc])
    }
  })
  |> result.map(fn(segments) { string.join(list.reverse(segments), "/") })
}
