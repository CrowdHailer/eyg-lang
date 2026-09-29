import eyg/cli/helpers
import eyg/cli/shell
import eyg/hub/cache
import eyg/interpreter/value as v
import eyg/parser
import gleam/dict
import gleam/string
import loam/execute
import loam/sandbox

pub fn type_test() {
  let assert #(sandbox.Returned(#(output, _)), _) =
    shell.handle("/type 5", [], [], state()) |> sandbox.run(sandbox.sandbox())
  assert [Ok("Integer")] == output
}

pub fn import_from_repl_working_directory_test() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_cwd("/project")
    |> sandbox.with_file(
      "/project/test/fixtures/source_relative/value.eyg",
      "5",
    )
  let assert #(sandbox.Returned(#(output, _)), _) =
    shell.handle(
      "import \"./test/fixtures/source_relative/value.eyg\"",
      [],
      [],
      state(),
    )
    |> sandbox.run(sandbox)
  assert [Ok("5")] == output
}

pub fn scope_test() {
  let assert #(
    sandbox.Returned(#(output, #(buffer, scope, defs, state))),
    sandbox,
  ) =
    shell.handle("let x = 1", [], [], state())
    |> sandbox.run(sandbox.sandbox())
  assert [] == output
  assert "" == buffer
  let assert #(sandbox.Returned(#(output, _)), _) =
    shell.handle("x", scope, defs, state) |> sandbox.run(sandbox)
  assert [Ok("1")] == output
}

pub fn scope_empty_test() {
  assert shell.render_scope([]) == "(no variables in scope)"
}

pub fn scope_lists_variables_oldest_first_test() {
  let scope = [#("count", v.Integer(2)), #("name", v.String("ada"))]
  assert shell.render_scope(scope) == "name = \"ada\"\ncount = 2"
}

pub fn scope_shows_a_shadowed_name_once_test() {
  let scope = [#("x", v.Integer(2)), #("x", v.Integer(1))]
  assert shell.render_scope(scope) == "x = 2"
}

pub fn type_of_requires_an_expression_test() {
  assert shell.type_of("", [], dict.new()) == "usage: :type <expression>"
}

pub fn type_of_integer_test() {
  assert shell.type_of("42", [], dict.new()) == "Integer"
}

pub fn type_of_string_test() {
  assert shell.type_of("\"hi\"", [], dict.new()) == "String"
}

pub fn type_of_builtin_application_test() {
  assert shell.type_of("!int_add(1, 2)", [], dict.new()) == "Integer"
}

pub fn type_of_uses_definitions_in_scope_test() {
  // `let x = 5` entered earlier; `/type x` should know its type.
  let assert Ok(#(#([def], _), _)) = parser.block_from_string("let x = 5")
  assert shell.type_of("x", [def], dict.new()) == "Integer"
}

pub fn type_of_reports_a_type_error_test() {
  let message = shell.type_of("!int_add(1, \"two\")", [], dict.new())
  assert string.starts_with(message, "type error:")
}

pub fn type_of_shows_performed_effects_test() {
  let message = shell.type_of("perform Log(\"hi\")", [], dict.new())
  assert string.contains(message, " ! <Log>")
}

pub fn type_of_of_a_pure_expression_has_no_effects_test() {
  // A pure expression must not gain an effect suffix.
  assert shell.type_of("42", [], dict.new()) == "Integer"
}

fn state() -> execute.State {
  execute.State(origin: helpers.config.client.origin, cache: cache.empty())
}
