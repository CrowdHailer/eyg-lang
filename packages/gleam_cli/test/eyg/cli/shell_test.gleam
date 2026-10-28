import eyg/cli/helpers
import eyg/cli/shell
import eyg/hub/cache
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/parser
import glasshouse/archive
import glasshouse/rerun
import glasshouse/run
import glasshouse/session
import gleam/dict
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import loam/execute
import loam/ir
import loam/sandbox
import loam/sandbox/fs
import loam/source
import loam/system
import multiformats/cid/v1

pub fn interactive_session_retains_modules_and_types_test() {
  let #(reference, sandbox) = module_server()
  let sandbox =
    with_lines(sandbox, ["let x = " <> reference, reference, "/type x", ""])
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    sandbox.run(shell.execute(None, helpers.config), sandbox)
  assert sandbox.network_state == 1
  assert list.contains(sandbox.stdout, "5")
  assert list.contains(sandbox.stdout, "Integer")
  assert sandbox.stderr == []
}

pub fn interactive_session_retains_modules_after_errors_test() {
  let #(reference, sandbox) = module_server()
  let sandbox =
    with_lines(sandbox, [
      "let x = " <> reference <> " missing_variable",
      reference,
      "/type " <> reference,
      "",
    ])
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    sandbox.run(shell.execute(None, helpers.config), sandbox)
  assert sandbox.network_state == 1
  assert list.contains(sandbox.stdout, "5")
  assert list.contains(sandbox.stdout, "Integer")
  let assert [error] = sandbox.stderr
  assert string.contains(error, "missing_variable")
}

pub fn interactive_session_retains_initialization_state_test() {
  list.each(["x", "perform Break({})"], fn(tail) {
    let #(reference, sandbox) = module_server()
    let input =
      source.Code(
        "{shell: (_) -> { let x = " <> reference <> " " <> tail <> " }}",
      )
    let sandbox = with_lines(sandbox, [reference, "/type " <> reference, ""])
    let assert #(sandbox.Returned(Ok(0)), sandbox) =
      sandbox.run(shell.execute(Some(input), helpers.config), sandbox)
    assert sandbox.network_state == 1
    assert list.contains(sandbox.stdout, "5")
    assert list.contains(sandbox.stdout, "Integer")
    assert sandbox.stderr == []
  })
}

fn module_server() {
  let module = ir.integer(5)
  let cid = helpers.cid_from_tree(module) |> v1.to_string
  let reply = response.new(200) |> response.set_body(dag_json.to_block(module))
  let sandbox =
    sandbox.with_network(
      sandbox.sandbox(),
      fn(request, count) {
        assert request.path == "/modules/" <> cid
        #(Ok(reply), count + 1)
      },
      0,
    )
  #("#" <> cid, sandbox)
}

fn with_lines(sandbox, lines) {
  list.fold(lines, sandbox, fn(sandbox, line) {
    sandbox.with_prompt_response(sandbox, Ok(line))
  })
}

pub fn multiline_input_preserves_token_boundaries_test() {
  let sandbox =
    with_lines(sandbox.sandbox(), [
      "let identity = (n) -> { let value = n",
      "value }",
      "identity(7)",
      "9",
      "",
    ])
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    sandbox.run(shell.execute(None, helpers.config), sandbox)
  assert sandbox.stderr == []
  assert list.reverse(sandbox.stdout)
    == ["type /help for shell commands", "> ", "> ", "> ", "7", "> ", "9", "> "]
}

pub fn multiline_comments_end_at_the_submitted_line_test() {
  let sandbox =
    with_lines(sandbox.sandbox(), [
      "let identity = (n) -> { // return n on the next line",
      "n }",
      "identity(3)",
      "",
    ])
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    sandbox.run(shell.execute(None, helpers.config), sandbox)
  assert sandbox.stderr == []
  assert list.reverse(sandbox.stdout)
    == ["type /help for shell commands", "> ", "> ", "> ", "3", "> "]
}

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
  execute.State(
    origin: helpers.config.client.origin,
    cache: cache.empty(),
    store: None,
  )
}

pub fn frontend_initialization_does_not_take_terminal_input_test() {
  let assert system.Done(Ok(#([], _))) = shell.initialize(None, helpers.config)
}

pub fn frontend_recording_retains_bindings_test() {
  let assert #(sandbox.Returned(#([], records, #("", scope, defs, state))), _) =
    shell.handle_recorded("let now = perform Now({})", [], [], state())
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_now(7))
  assert records == [#("Now", v.unit(), v.Integer(7))]
  let assert #(sandbox.Returned(#([Ok("7")], [], _)), _) =
    shell.handle_recorded("now", scope, defs, state)
    |> sandbox.run(sandbox.sandbox())
}

pub fn bindings_in_one_cell_are_visible_to_later_closures_test() {
  let code = "let x = 3 let add = (n) -> { !int_add(x, n) } add(2)"
  let assert #(sandbox.Returned(#(output, _)), _) =
    shell.handle(code, [], [], state()) |> sandbox.run(sandbox.sandbox())
  assert output == [Ok("5")]
}

pub fn same_cell_shadowing_agrees_with_later_calls_and_types_test() {
  let sandbox =
    with_lines(sandbox.sandbox(), [
      "let x = 3 let x = 8 let add = (n) -> { !int_add(x, n) }", "add(2)",
      "/t add(2)", "",
    ])
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    sandbox.run(shell.execute(None, helpers.config), sandbox)
  assert list.contains(sandbox.stdout, "10")
  assert list.contains(sandbox.stdout, "Integer")
  assert sandbox.stderr == []
}

pub fn recorded_shell_sessions_replay_test() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_cwd("/work")
    |> sandbox.with_directory("/work")
    |> sandbox.with_env("EYG_TRACE_DIR", "/traces")
    |> sandbox.with_random_values([3])
    |> with_lines([
      "let n = 2 let x = !int_add(n, 3)",
      "perform WriteFile({path: \"a.txt\", contents: !string_to_binary(!int_to_string(x))})",
      "/scope",
      "!int_add(x, 1)",
      "",
    ])
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    sandbox.run(shell.record(helpers.config), sandbox)
  assert list.contains(sandbox.stdout, "6")
  assert fs.read(sandbox.file_system, "/work/a.txt") == Ok("5")
  let assert Ok(fs.Directory(children:, ..)) =
    fs.inspect(sandbox.file_system, "/traces")
  let assert [name] = dict.keys(children)
  let assert Ok(text) = fs.read(sandbox.file_system, "/traces/" <> name)
  let assert Ok(archive) = archive.from_string(text)
  let runs = session.runs(archive.session)
  assert list.map(runs, fn(run) { run.code })
    == [
      "let n = 2 let x = !int_add(n, 3)",
      "perform WriteFile({path: \"a.txt\", contents: !string_to_binary(!int_to_string(x))})",
      "!int_add(x, 1)",
    ]
  assert list.all(runs, fn(r) { r.kind == run.Cell })
  let reports = rerun.session(archive.session, archive.store)
  assert list.all(reports, fn(report) { report.problem == None })
}
