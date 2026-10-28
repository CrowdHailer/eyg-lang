import eyg/cli/captured
import eyg/interpreter/expression
import eyg/interpreter/value
import eyg/ir/dag_json as ir_json
import eyg/ir/tree as ir
import gleam/string
import loam/source

fn meta() {
  source.Location(source.Inline, source.Json)
}

pub fn captures_only_the_variables_a_function_uses_test() {
  let body = ir.variable("offset") |> ir.map_annotation(fn(_) { meta() })
  let closure =
    value.Closure("_", body, [
      #("offset", value.Integer(42)),
      #("unused", value.Partial(value.Resume(Nil), [])),
    ])
  let assert Ok(program) = captured.program(closure, meta(), "/project")
  assert !string.contains(ir_json.to_string(program), "unused")
  assert ir.free_variables(program, []) == []
}

pub fn a_used_continuation_is_rejected_before_capture_test() {
  let body = ir.variable("resume") |> ir.map_annotation(fn(_) { meta() })
  let closure =
    value.Closure("_", body, [
      #("resume", value.Partial(value.Resume(Nil), [])),
    ])
  let assert Error(reason) = captured.program(closure, meta(), "/project")
  assert string.contains(reason, "continuation")
}

pub fn function_imports_keep_their_own_file_origin_test() {
  let assert Ok(code) =
    source.parse(
      "(_) -> { import \"./number.eyg\" }",
      source.Disk("/repo/lib/context.eyg"),
    )
  let assert Ok(closure) = expression.execute(code, [])
  let assert Ok(program) = captured.program(closure, meta(), "/project")
  assert ir.list_references(program) == [ir.Relative("/repo/lib/number.eyg")]
}

pub fn interactive_function_imports_use_the_explicit_invocation_root_test() {
  let assert Ok(code) =
    source.parse("(_) -> { import \"./number.eyg\" }", source.Inline)
  let assert Ok(closure) = expression.execute(code, [])
  let assert Ok(program) = captured.program(closure, meta(), "/project")
  assert ir.list_references(program) == [ir.Relative("/project/number.eyg")]
}
