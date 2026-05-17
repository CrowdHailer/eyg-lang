import birdie
import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/interpreter/expression
import gleam/string
import simplifile
import touch_grass/file_system/append_file
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file

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

pub fn write_file_test() {
  let _ = simplifile.delete_file("./test/fixtures/write.txt")
  let input = write_file.Input(path: "write.txt", contents: <<"test content">>)
  let assert Ok(Nil) = execute.write_file("./test/fixtures", input)
  let read_input =
    read_file.Input(path: "write.txt", offset: 0, limit: 1_000_000)
  let assert Ok(contents) = execute.read_file("./test/fixtures", read_input)
  assert <<"test content">> == contents
  let assert Ok(Nil) = simplifile.delete_file("./test/fixtures/write.txt")
}

pub fn write_file_invalid_path_test() {
  let path = string.repeat("../", 100)
  let input = write_file.Input(path:, contents: <<"data">>)
  let assert Error(_) = execute.write_file("./test/fixtures", input)
}

pub fn append_file_test() {
  let _ = simplifile.delete_file("./test/fixtures/append.txt")
  let reset = write_file.Input(path: "append.txt", contents: <<"start">>)
  let assert Ok(Nil) = execute.write_file("./test/fixtures", reset)
  let input = append_file.Input(path: "append.txt", contents: <<" end">>)
  let assert Ok(Nil) = execute.append_file("./test/fixtures", input)
  let read_input =
    read_file.Input(path: "append.txt", offset: 0, limit: 1_000_000)
  let assert Ok(contents) = execute.read_file("./test/fixtures", read_input)
  assert <<"start end">> == contents
  let assert Ok(Nil) = simplifile.delete_file("./test/fixtures/append.txt")
}

/// Run a snippet of EYG source text and capture the formatted runtime error.
fn snap_text(code: String) -> String {
  let assert Ok(node) = source.parse_input(code, source.Code(code))
  let assert Error(#(reason, location, _env, _k)) = expression.execute(node, [])
  execute.render_error(reason, location, "")
}

pub fn undefined_variable_test() {
  snap_text("unknown")
  |> birdie.snap(title: "runtime: undefined variable")
}

pub fn undefined_variable_multiline_test() {
  snap_text("let x = 1\nlet y = 2\nunknown")
  |> birdie.snap(title: "runtime: undefined variable on third line")
}

pub fn undefined_builtin_test() {
  snap_text("!nonexistent_builtin")
  |> birdie.snap(title: "runtime: undefined builtin")
}

pub fn not_a_function_test() {
  snap_text("5(1)")
  |> birdie.snap(title: "runtime: not a function")
}

pub fn missing_field_test() {
  snap_text("{a: 1}.b")
  |> birdie.snap(title: "runtime: missing record field")
}

pub fn abort_test() {
  snap_text("perform Abort(\"oops\")")
  |> birdie.snap(title: "runtime: abort effect")
}

pub fn unhandled_effect_test() {
  snap_text("perform Custom(1)")
  |> birdie.snap(title: "runtime: unhandled custom effect")
}

pub fn multi_line_span_test() {
  // Without a trailing comma, the record's whole span survives the parser
  // and the renderer underlines every line the expression covers.
  snap_text("{a: 1\n}.b")
  |> birdie.snap(title: "runtime: multi-line span")
}
