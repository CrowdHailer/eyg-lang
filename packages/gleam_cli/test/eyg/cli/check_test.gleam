import eyg/cli/check
import eyg/cli/helpers
import eyg/cli/internal/source
import gleam/string
import multiformats/cid/v1

pub fn check_simple_expression_test() {
  let input = source.Code("3")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(helpers.sandbox())
  assert Ok(0) == output
  assert ["Integer"] == sandbox.stdout
}

pub fn check_fails_test() {
  let input = source.Code("x")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(helpers.sandbox())
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
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(sandbox)
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
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(sandbox)
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
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(sandbox)
  assert ["{}"] == sandbox.stdout
  assert Ok(0) == output
}

pub fn check_fails_unknown_import_test() {
  let files = [#("/main.eyg", "import \"/lib/foo.eyg\"")]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(sandbox)
  assert Error("") == output
  let assert [e] = sandbox.stdout
  assert string.contains(e, "missing reference")
}

pub fn check_out_of_range_import_test() {
  let files = [#("/main.eyg", "import \"../../foo.eyg\"")]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(sandbox)
  assert Error("") == output
  let assert [e] = sandbox.stdout
  assert string.contains(e, "missing reference")
}

pub fn check_fail_recursive_test() {
  let files = [#("/main.eyg", "import \"/main.eyg\"")]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(sandbox)
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
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(sandbox)
  assert Error("") == output
  let assert [e] = sandbox.stdout
  assert string.contains(e, "missing reference")
}

pub fn check_fails_unknown_ref_test() {
  let #(cid, _src) = helpers.random_code()
  let sandbox = helpers.sandbox()
  let input = source.Code("#" <> v1.to_string(cid))
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(sandbox)
  let assert Error("") = output
  let assert [message] = sandbox.stdout
  assert string.contains(message, "missing reference")
}
