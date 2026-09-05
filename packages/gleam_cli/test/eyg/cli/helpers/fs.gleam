import filepath
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import simplifile.{type FileError, type FilePermissions}

pub fn rw() {
  set.from_list([simplifile.Read, simplifile.Write])
}

pub fn rwx() {
  set.from_list([simplifile.Read, simplifile.Write, simplifile.Execute])
}

fn permissions_file() {
  simplifile.FilePermissions(user: rw(), group: rw(), other: rw())
}

fn permissions_directory() {
  simplifile.FilePermissions(user: rwx(), group: rwx(), other: rwx())
}

pub type Entry {
  File(contents: BitArray, permissions: FilePermissions)
  Directory(children: Dict(String, Entry), permissions: FilePermissions)
}

pub fn directory(children: List(#(String, Entry))) -> Entry {
  Directory(
    children: dict.from_list(children),
    permissions: permissions_directory(),
  )
}

pub fn file(contents: String) -> Entry {
  File(contents: <<contents:utf8>>, permissions: permissions_file())
}

fn path_parts(path) {
  case string.contains(path, "\u{0}") {
    True -> Error(simplifile.Unknown("ERR_INVALID_ARG_VALUE"))
    False ->
      // filepath.expand doesn't leave paths beginning double slash as implementation specific.
      case filepath.expand(path) {
        Ok("/" <> rest) -> Ok(string.split(rest, "/"))
        Ok(_relative) -> panic as "unsupported"
        Error(Nil) -> panic as "unsupported"
      }
  }
}

pub fn inspect(fs, path) {
  let directory = string.ends_with(path, "/")
  use parts <- result.try(path_parts(path))
  use entry <- result.try(do_follow(fs, parts))
  case entry {
    File(..) if directory -> Error(simplifile.Enotdir)
    _ -> Ok(entry)
  }
}

fn do_follow(fs: Entry, segments: List(String)) -> Result(Entry, FileError) {
  case segments, fs {
    [], _ -> Ok(fs)
    [name, ..rest], Directory(children:, ..) ->
      case dict.get(children, name) {
        Ok(fs) -> do_follow(fs, rest)
        Error(_) -> Error(simplifile.Enoent)
      }
    [_, ..], _ -> Error(simplifile.Enotdir)
  }
}

pub fn read(file_system: Entry, path: String) -> Result(String, FileError) {
  use entry <- result.try(inspect(file_system, path))
  case entry {
    File(contents:, ..) ->
      bit_array.to_string(contents) |> result.replace_error(simplifile.NotUtf8)
    Directory(..) -> Error(simplifile.Eisdir)
  }
}

pub fn read_directory(
  file_system: Entry,
  path: String,
) -> Result(List(String), FileError) {
  use entry <- result.try(inspect(file_system, path))
  case entry {
    File(..) -> Error(simplifile.Enotdir)
    Directory(children:, ..) ->
      Ok(dict.keys(children) |> list.sort(string.compare))
  }
}

pub fn transform(
  file_system: Entry,
  path: String,
  func: fn(Result(Entry, Nil)) -> Result(Entry, simplifile.FileError),
) {
  use parts <- result.try(path_parts(path))
  do_transform(Ok(file_system), parts, func)
}

fn do_transform(
  file_system: Result(Entry, Nil),
  parts: List(String),
  func: fn(Result(Entry, Nil)) -> Result(Entry, FileError),
) -> Result(Entry, FileError) {
  case parts, file_system {
    [], any -> func(any)
    [part, ..rest], Ok(Directory(children:, permissions:)) -> {
      use child <- result.try(do_transform(dict.get(children, part), rest, func))
      Ok(Directory(dict.insert(children, part, child), permissions))
    }
    [_, ..], Ok(File(..)) -> Error(simplifile.Enotdir)
    [_, ..], Error(Nil) -> Error(simplifile.Enoent)
  }
}

pub fn write(
  file_system: Entry,
  path: String,
  contents: String,
) -> #(Result(Nil, FileError), Entry) {
  let directory = string.ends_with(path, "/")
  transform(file_system, path, fn(entry) {
    case entry {
      Ok(File(..)) if directory -> Error(simplifile.Eisdir)
      Ok(File(permissions:, ..)) -> Ok(File(<<contents:utf8>>, permissions))
      Ok(Directory(..)) -> Error(simplifile.Eisdir)
      Error(Nil) -> Ok(File(<<contents:utf8>>, permissions_file()))
    }
  })
  |> update_result(file_system)
}

pub fn create_directory(
  file_system: Entry,
  path: String,
) -> #(Result(Nil, FileError), Entry) {
  case path_parts(path) {
    Error(error) -> #(Error(error), file_system)
    Ok(parts) ->
      case create_directory_parts(file_system, parts) {
        Ok(file_system) -> #(Ok(Nil), file_system)
        Error(error) -> #(Error(error), file_system)
      }
  }
}

fn create_directory_parts(file_system, parts) {
  case parts, file_system {
    [], Directory(..) -> Ok(file_system)
    [], File(..) -> Error(simplifile.Eexist)
    [name, ..rest], Directory(children:, permissions:) -> {
      let child = case dict.get(children, name) {
        Ok(child) -> child
        Error(Nil) -> directory([])
      }
      use child <- result.try(create_directory_parts(child, rest))
      Ok(Directory(dict.insert(children, name, child), permissions))
    }
    [_, ..], File(..) -> Error(simplifile.Enotdir)
  }
}

pub fn set_permissions(
  file_system: Entry,
  path: String,
  octal: Int,
) -> #(Result(Nil, FileError), Entry) {
  let directory = string.ends_with(path, "/")
  let transformed = {
    use permissions <- result.try(permissions(octal))
    transform(file_system, path, fn(entry) {
      case entry {
        Ok(File(..)) if directory -> Error(simplifile.Enotdir)
        Ok(File(contents:, ..)) -> Ok(File(contents, permissions))
        Ok(Directory(children:, ..)) -> Ok(Directory(children, permissions))
        Error(Nil) -> Error(simplifile.Enoent)
      }
    })
  }
  update_result(transformed, file_system)
}

fn update_result(
  transformed: Result(Entry, FileError),
  original: Entry,
) -> #(Result(Nil, FileError), Entry) {
  case transformed {
    Ok(file_system) -> #(Ok(Nil), file_system)
    Error(error) -> #(Error(error), original)
  }
}

fn permissions(octal) -> Result(FilePermissions, FileError) {
  case octal >= 0 && octal <= 0o777 {
    False -> Error(simplifile.Einval)
    True -> {
      let classes =
        list.map([6, 3, 0], fn(shift) {
          let bits = int.bitwise_shift_right(octal, shift)
          [
            #(4, simplifile.Read),
            #(2, simplifile.Write),
            #(1, simplifile.Execute),
          ]
          |> list.filter_map(fn(pair) {
            case int.bitwise_and(bits, pair.0) != 0 {
              True -> Ok(pair.1)
              False -> Error(Nil)
            }
          })
          |> set.from_list
        })
      let assert [user, group, other] = classes
      Ok(simplifile.FilePermissions(user:, group:, other:))
    }
  }
}
