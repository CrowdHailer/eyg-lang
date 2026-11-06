import cloud/code
import cloud/shell

pub fn statements_are_lines_test() {
  let assert Ok(source) = shell.parse("let x = 1\n!int_add(x, 2)")
  assert code.to_text(source) == "let x = 1\n!int_add(x, 2)"
}

pub fn records_test() {
  let assert Ok(source) = shell.parse("{a: 1, b: \"two\"}")
  assert code.to_text(source) == "{a: 1, b: \"two\"}"
}
