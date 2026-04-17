import eyg/cli/internal/execute
import gleam/string
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file

pub fn read_whole_file_test() {
  let input = read_file.Input(path: "hello.txt", offset: 0, limit: 1_000_000)
  let assert Ok(contents) = execute.read_file("./test/fixtures", input)
  assert <<"Hello, World!">> == contents
}

pub fn read_empty_file_test() {
  let input = read_file.Input(path: "empty.txt", offset: 0, limit: 1_000_000)
  let assert Ok(contents) = execute.read_file("./test/fixtures", input)
  assert <<>> == contents
}

pub fn read_subset_test() {
  let input = read_file.Input(path: "hello.txt", offset: 0, limit: 5)
  let assert Ok(contents) = execute.read_file("./test/fixtures", input)
  assert <<"Hello">> == contents
}

pub fn read_offset_test() {
  let input = read_file.Input(path: "hello.txt", offset: 7, limit: 1_000_000)
  let assert Ok(contents) = execute.read_file("./test/fixtures", input)
  assert <<"World!">> == contents
}

pub fn invalid_path_test() {
  let path = string.repeat("../", 100)
  let input = read_file.Input(path:, offset: 0, limit: 1_000_000)
  let assert Error(contents) = execute.read_file("./test/fixtures", input)
  assert "No such file or directory" == contents
}

pub fn unknown_path_test() {
  let input = read_file.Input(path: "unknown.txt", offset: 0, limit: 1_000_000)
  let assert Error(contents) = execute.read_file("./test/fixtures", input)
  assert "No such file or directory" == contents
}

pub fn read_directory_test() {
  let assert Ok(contents) =
    execute.read_directory("./test/fixtures", path: "dir")
  assert [
      #("a.txt", read_directory.File(size: 1)),
      #("subdir", read_directory.Directory),
    ]
    == contents
}
