import eyg/cli/internal/source
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/string
import multiformats/cid/v1

pub fn read_code_test() {
  let assert Ok(code) =
    source.Code("!int_add(1, 1)")
    |> source.read_input()
  let assert Ok(source) = source.parse_input(code, source.Stdin)
  assert ir.apply(ir.apply(ir.builtin("int_add"), ir.integer(1)), ir.integer(1))
    == ir.clear_annotation(source)
}

pub fn explicit_reference_forms_test() {
  let cid = dag_json.vacant_cid
  let encoded_cid = v1.to_string(cid)

  assert ir.package("standard") == parse_reference("@standard")
  assert ir.version("standard", 3) == parse_reference("@standard:3")
  assert ir.release("standard", 3, cid)
    == parse_reference("@standard:3:" <> encoded_cid)
  assert ir.reference(cid) == parse_reference("#" <> encoded_cid)
  assert ir.relative("./index.eyg") == parse_reference("import \"./index.eyg\"")
}

fn parse_reference(code: String) {
  let assert Ok(parsed) = source.parse_input(code, source.Code(code))
  ir.clear_annotation(parsed)
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
