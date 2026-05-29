import eyg/cli/internal/source
import eyg/ir/tree as ir
import gleam/string

pub fn read_code_test() {
  let assert Ok(code) =
    source.Code("!int_add(1, 1)")
    |> source.read_input()
  let assert Ok(source) = source.parse_input(code, source.Stdin)
  assert ir.apply(ir.apply(ir.builtin("int_add"), ir.integer(1)), ir.integer(1))
    == ir.clear_annotation(source)
}

pub fn missing_file_error_test() {
  let path = "/this/path/definitely/does/not/exist.eyg"
  let assert Error(msg) =
    source.File(path)
    |> source.read_input()
  // Wraps the OS error in the standard `error:` / `hint:` format
  // and includes the missing path so it's diagnosable.
  assert string.starts_with(msg, "error: ")
  assert string.contains(msg, path)
  assert string.contains(msg, "hint: ")
}
