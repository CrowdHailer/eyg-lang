import cloud/fs
import cloud/shell.{Failure, Hint, Result, Stdout}
import cloud/store
import gleam/string
import morph/editable as e

fn setup() {
  let s = store.new()
  #(s, shell.start(s))
}

/// Commands are written as source here and parsed into the editor's tree.
fn run(s, code, snapshot) {
  let assert Ok(source) = shell.parse(code)
  shell.run(s, source, snapshot)
}

pub fn evaluates_expression_test() {
  let #(s, start) = setup()
  let #(output, _) = run(s, "!int_add(1, 2)", start)
  assert output == [Result("3")]
}

pub fn let_bindings_persist_in_scope_test() {
  let #(s, start) = setup()
  let #(output, next) = run(s, "let x = 5", start)
  assert output == []
  let #(output, _) = run(s, "!int_add(x, 1)", next)
  assert output == [Result("6")]
}

pub fn parse_assignments_without_a_value_test() {
  let assert Ok(e.Block([_], e.Vacant, _)) = shell.parse("let x = 5")
}

pub fn parse_error_test() {
  let assert Error(_) = shell.parse("let = 1")
}

pub fn standard_out_test() {
  let #(s, start) = setup()
  let #(output, _) = run(s, "perform StandardOut(\"hi\\n\")", start)
  assert output == [Stdout("hi\n"), Result("{}")]
}

pub fn write_and_read_file_test() {
  let #(s, start) = setup()
  let #(_, next) =
    run(
      s,
      "perform WriteFile({path: \"/a.txt\", contents: !string_to_binary(\"abc\")})",
      start,
    )
  assert fs.read_file(s, next.root, "/a.txt") == Ok(<<"abc">>)
  assert next.root != start.root
  let #(output, _) =
    run(s, "perform ReadFile({path: \"a.txt\", offset: 1, limit: 10})", next)
  let assert [Result(text)] = output
  assert string.starts_with(text, "Ok(")
}

pub fn failed_command_keeps_root_and_scope_test() {
  let #(s, start) = setup()
  let code =
    "let _ = perform WriteFile({path: \"f\", contents: !string_to_binary(\"x\")})
let y = 1
missing"
  let #(output, after) = run(s, code, start)
  let assert [Failure(message), Hint(_)] = output
  assert string.contains(message, "variable undefined: missing")
  assert after == start
}

pub fn unsupported_effect_test() {
  let #(s, start) = setup()
  let #(output, after) = run(s, "perform Exit(1)", start)
  let assert [Failure(message), Hint(_)] = output
  assert string.contains(message, "unhandled effect Exit")
  assert after == start
}

pub fn statements_run_in_order_test() {
  let #(s, start) = setup()
  let #(output, _) =
    run(
      s,
      "let a = 1\nlet b = !int_add(a, 1)\nlet a = 10\n!int_add(a, b)",
      start,
    )
  assert output == [Result("12")]
}
