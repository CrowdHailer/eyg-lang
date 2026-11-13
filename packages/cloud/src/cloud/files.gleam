//// Seed private in-memory session roots from read-only startup inputs.

import cloud/beam/file_system
import filepath
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile

pub type Operation {
  Write(BitArray)
  Append(BitArray)
  Delete
  MakeDirectory
}

pub fn seed(directory, blocks) {
  let fs = file_system.new(blocks)
  case directory {
    None -> Ok(fs)
    Some(directory) -> copy_in(fs, directory, "/")
  }
}

fn copy_in(fs, directory, path) {
  use names <- result.try(
    simplifile.read_directory(directory)
    |> result.map_error(simplifile.describe_error),
  )
  list.try_fold(list.sort(names, string.compare), fs, fn(fs, name) {
    let source = filepath.join(directory, name)
    let target = filepath.join(path, name)
    case simplifile.is_directory(source) {
      Ok(True) -> {
        let #(created, fs) = file_system.make_directory(fs, target)
        use _ <- result.try(created)
        copy_in(fs, source, target)
      }
      _ -> {
        use contents <- result.try(
          simplifile.read_bits(source)
          |> result.map_error(simplifile.describe_error),
        )
        let #(written, fs) = file_system.write(fs, target, contents)
        result.replace(written, fs)
      }
    }
  })
}

pub fn normalize(path: String) -> String {
  filepath.expand(filepath.join("/", path)) |> result.unwrap("/")
}

pub fn slice(bytes: BitArray, offset: Int, limit: Int) -> BitArray {
  let size = bit_array.byte_size(bytes)
  let offset = int.clamp(offset, 0, size)
  let limit = int.clamp(limit, 0, size - offset)
  bit_array.slice(bytes, offset, limit) |> result.unwrap(<<>>)
}
