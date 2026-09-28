import eyg/cli/check
import eyg/cli/helpers
import gleam/string
import loam/sandbox
import loam/source
import multiformats/cid/v1

pub fn check_simple_expression_test() {
  let input = source.Code("3")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox.sandbox())
  assert Ok(0) == output
  assert ["Integer"] == sandbox.stdout
}

pub fn check_fails_test() {
  let input = source.Code("x")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox.sandbox())
  let assert Error("") = output
  let assert [message] = sandbox.stdout
  assert string.contains(message, "missing variable")
}

pub fn check_pulls_absolute_deps_test() {
  let files = [
    #("/main.eyg", "import \"/lib/foo.eyg\""),
    #("/lib/foo.eyg", "\"Hi\""),
  ]
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_files(files)
  let input = source.File("/main.eyg")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert Ok(0) == output
  assert ["String"] == sandbox.stdout
}

// TODO pull from CWD
pub fn check_gathers_errors_test() {
  let files = [
    #(
      "/main.eyg",
      "let x = import \"/lib/foo.eyg\"
y",
    ),
    #("/lib/foo.eyg", "z"),
  ]
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_files(files)
  let input = source.File("/main.eyg")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert Error("") == output
  let assert [e1, e2] = sandbox.stdout
  assert string.contains(e1, "missing variable 'y'")
  assert string.contains(e2, "missing variable 'z'")
}

pub fn check_pulls_relative_deps_test() {
  let files = [
    #("/main.eyg", "import \"./lib/a.eyg\""),
    #("/lib/a.eyg", "import \"./b.eyg\""),
    #("/lib/b.eyg", "{}"),
  ]
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_files(files)
  let input = source.File("/main.eyg")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert ["{}"] == sandbox.stdout
  assert Ok(0) == output
}

pub fn check_relative_input_imports_above_its_directory_test() {
  let files = [
    #("/project/index.eyg", "{}"),
    #("/project/examples/entry.eyg", "import \"./uptime.eyg\""),
    #("/project/examples/uptime.eyg", "import \"../index.eyg\""),
  ]
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_files(files)
    |> sandbox.with_cwd("/project/examples")
  let input = source.File("entry.eyg")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert ["{}"] == sandbox.stdout
  assert Ok(0) == output
}

pub fn check_inline_code_imports_from_cwd_test() {
  let files = [#("/project/lib.eyg", "\"Hi\"")]
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_files(files)
    |> sandbox.with_cwd("/project/examples")
  let input = source.Code("import \"../lib.eyg\"")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert ["String"] == sandbox.stdout
  assert Ok(0) == output
}

pub fn check_fails_unknown_import_test() {
  let files = [#("/main.eyg", "import \"/lib/foo.eyg\"")]
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_files(files)
  let input = source.File("/main.eyg")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert Error("") == output
  let assert [e] = sandbox.stdout
  assert string.contains(e, "missing reference")
}

pub fn check_out_of_range_import_test() {
  let files = [#("/main.eyg", "import \"../../foo.eyg\"")]
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_files(files)
  let input = source.File("/main.eyg")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert Error("") == output
  let assert [e] = sandbox.stdout
  assert string.contains(e, "missing reference")
}

pub fn check_fail_recursive_test() {
  let files = [#("/main.eyg", "import \"/main.eyg\"")]
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_files(files)
  let input = source.File("/main.eyg")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert Error("") == output
  let assert [e] = sandbox.stdout
  assert string.contains(e, "missing reference")
}

pub fn check_fails_bad_import_test() {
  let files = [
    #("/main.eyg", "import \"/lib/foo.eyg\""),
    #("/lib/foo.eyg", ":"),
  ]
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_files(files)
  let input = source.File("/main.eyg")
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert Error("") == output
  let assert [e] = sandbox.stdout
  assert string.contains(e, "missing reference")
}

pub fn check_fails_unknown_ref_test() {
  let #(cid, _src) = helpers.random_code()
  let sandbox = sandbox.sandbox()
  let input = source.Code("#" <> v1.to_string(cid))
  let assert #(sandbox.Returned(output), sandbox) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  let assert Error("") = output
  let assert [message] = sandbox.stdout
  assert string.contains(message, "missing reference")
}
