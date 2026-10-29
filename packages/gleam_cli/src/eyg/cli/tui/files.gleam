//// File and directory suggestions for the import picker.

import filepath
import gleam/list
import gleam/string
import loam/system
import simplifile

pub type Entry {
  Entry(name: String, directory: Bool)
}

/// Preserve the directory prefix exactly as typed, including its trailing slash.
pub fn directory(typed: String) -> String {
  case string.split(typed, "/") |> list.reverse {
    [] | [_] -> ""
    [_, ..parents] ->
      parents
      |> list.reverse
      |> string.join("/")
      |> string.append("/")
  }
}

pub fn list(directory: String) -> system.Effect(List(Entry)) {
  let path = case directory {
    "" -> "."
    directory -> directory
  }
  use names <- system.then(system.read_directory(path))
  case names {
    Ok(names) -> classify(path, list.sort(names, string.compare), [])
    Error(_) -> system.Done([])
  }
}

fn classify(path, names, acc) {
  case names {
    [] -> system.Done(list.reverse(acc))
    [name, ..rest] -> {
      use info <- system.then(system.file_info(filepath.join(path, name)))
      let directory = case info {
        Ok(system.Metadata(kind: simplifile.Directory, ..)) -> True
        _ -> False
      }
      classify(path, rest, [Entry(name, directory), ..acc])
    }
  }
}

/// Hidden entries appear once the filename starts with a dot.
pub fn choices(directory: String, typed: String, entries: List(Entry)) {
  let hidden =
    string.starts_with(string.drop_start(typed, string.length(directory)), ".")
  entries
  |> list.filter(fn(entry) { hidden || !string.starts_with(entry.name, ".") })
  |> list.map(fn(entry) {
    case entry.directory {
      True -> #(directory <> entry.name <> "/", "directory")
      False -> #(directory <> entry.name, "file")
    }
  })
}
