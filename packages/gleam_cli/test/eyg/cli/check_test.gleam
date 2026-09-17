import eyg/cli/check
import eyg/cli/helpers
import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/hub/publisher
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import gleam/bit_array
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import multiformats/cid/v1
import ogre/origin
import untethered/ledger/schema
import untethered/substrate

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

pub fn check_relative_input_imports_above_its_directory_test() {
  let files = [
    #("/project/index.eyg", "{}"),
    #("/project/examples/entry.eyg", "import \"./uptime.eyg\""),
    #("/project/examples/uptime.eyg", "import \"../index.eyg\""),
  ]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
    |> helpers.with_cwd("/project/examples")
  let input = source.File("entry.eyg")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(sandbox)
  assert ["{}"] == sandbox.stdout
  assert Ok(0) == output
}

pub fn check_inline_code_imports_from_cwd_test() {
  let files = [#("/project/lib.eyg", "\"Hi\"")]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
    |> helpers.with_cwd("/project/examples")
  let input = source.Code("import \"../lib.eyg\"")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(sandbox)
  assert ["String"] == sandbox.stdout
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

fn module(code) {
  let assert Ok(tree) = parser.all_from_string(code)
  let tree = ir.map_annotation(tree, fn(_) { Nil })
  #(helpers.cid_from_tree(tree), tree)
}

fn release(package, version, cursor, module) {
  let payload =
    publisher.first(module, "test-key", package, module)
    |> fn(entry) {
      substrate.Entry(
        ..entry,
        sequence: version,
        content: publisher.Release(package, version, module),
      )
    }
    |> publisher.encode
    |> json.to_string
  schema.ArchivedEntry(
    cursor:,
    cid: module,
    payload:,
    entity: module,
    sequence: version,
    previous: None,
    type_: "release",
  )
}

// Serve one release per page to exercise the same cursor-based pull used by
// the CLI. Requests are recorded so cache behavior is observable in tests.
fn hub(sandbox, entries: List(schema.ArchivedEntry), modules) {
  let modules =
    list.map(modules, fn(pair) {
      let #(cid, tree) = pair
      #("/modules/" <> v1.to_string(cid), dag_json.to_block(tree))
    })
  helpers.with_network(
    sandbox,
    fn(request, requests) {
      let reply = case request.path {
        "/packages/pull" -> {
          let parameters = schema.pull_parameters_from_request(request)
          let entries =
            entries
            |> list.filter(fn(entry) { entry.cursor > parameters.since })
            |> list.take(1)
          response.new(200)
          |> response.set_body(
            entries
            |> schema.entries_response_encode
            |> json.to_string
            |> bit_array.from_string,
          )
        }
        path ->
          case list.key_find(modules, path) {
            Ok(body) -> response.new(200) |> response.set_body(body)
            Error(_) -> response.new(404) |> response.set_body(<<>>)
          }
      }
      #(Ok(reply), [request, ..requests])
    },
    [],
  )
}

pub fn check_fetches_content_and_transitive_dependencies_test() {
  let child = module("41")
  let parent = module("!int_add(#" <> v1.to_string(child.0) <> ", 1)")
  let sandbox = hub(helpers.sandbox(), [], [child, parent])
  let #(output, sandbox) =
    check.execute(source.Code("#" <> v1.to_string(parent.0)), helpers.config)
    |> helpers.run(sandbox)
  assert Ok(0) == output
  assert ["Integer"] == sandbox.stdout
  assert 2 == list.length(sandbox.network_state)
  assert list.all(sandbox.network_state, fn(request) {
    string.starts_with(request.path, "/modules/")
  })
}

pub fn check_resolves_latest_version_and_pin_from_configured_hub_test() {
  let first = module("1")
  let latest = module("\"latest\"")
  let sandbox =
    hub(
      helpers.sandbox(),
      [release("sample", 1, 1, first.0), release("sample", 2, 2, latest.0)],
      [first, latest],
    )
  let config =
    config.Config(
      ..helpers.config,
      client: client.Client(origin.https("custom.example")),
    )
  let input =
    source.Code(
      "{latest: @sample, first: @sample:1, pinned: @sample:1:"
      <> v1.to_string(first.0)
      <> "}",
    )
  let #(output, sandbox) = check.execute(input, config) |> helpers.run(sandbox)
  assert Ok(0) == output
  let assert [type_] = sandbox.stdout
  assert string.contains(type_, "latest: String")
  assert string.contains(type_, "first: Integer")
  assert string.contains(type_, "pinned: Integer")
  // Three ledger pages and two distinct modules, regardless of reference form.
  assert 5 == list.length(sandbox.network_state)
  assert list.all(sandbox.network_state, fn(request) {
    request.host == "custom.example"
  })
}

pub fn check_remote_dependencies_inside_local_imports_share_cache_test() {
  let identity = module("(value) -> { value }")
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files([
      #("/main.eyg", "{a: import \"./a.eyg\", b: import \"./b.eyg\"}"),
      #("/a.eyg", "@identity(42)"),
      #("/b.eyg", "@identity(\"hello\")"),
    ])
    |> hub([release("identity", 1, 1, identity.0)], [identity])
  let #(output, sandbox) =
    check.execute(source.File("/main.eyg"), helpers.config)
    |> helpers.run(sandbox)
  assert Ok(0) == output
  assert ["{a: Integer, b: String}"] == sandbox.stdout
  assert 3 == list.length(sandbox.network_state)
}

pub fn check_resolves_pins_inside_fetched_modules_test() {
  let child = module("\"hello\"")
  let parent = module("@sample:1:" <> v1.to_string(child.0))
  let sandbox =
    hub(helpers.sandbox(), [release("sample", 1, 1, child.0)], [parent, child])
  let #(output, sandbox) =
    check.execute(source.Code("#" <> v1.to_string(parent.0)), helpers.config)
    |> helpers.run(sandbox)
  assert Ok(0) == output
  assert ["String"] == sandbox.stdout
  assert 4 == list.length(sandbox.network_state)
}

pub fn check_rejects_mismatched_pins_even_if_content_is_cached_test() {
  let first = module("1")
  let other = module("\"other\"")
  let sandbox =
    hub(helpers.sandbox(), [release("sample", 1, 1, first.0)], [first, other])
  let input =
    source.Code(
      "let cached = #"
      <> v1.to_string(other.0)
      <> " @sample:1:"
      <> v1.to_string(other.0),
    )
  let #(output, sandbox) =
    check.execute(input, helpers.config) |> helpers.run(sandbox)
  assert Error("") == output
  let assert [message] = sandbox.stdout
  assert string.contains(message, "missing reference @sample:1:")
  assert 3 == list.length(sandbox.network_state)
}

pub fn check_rejects_missing_packages_versions_and_pins_test() {
  let first = module("1")
  let sandbox =
    hub(helpers.sandbox(), [release("sample", 1, 1, first.0)], [first])
  list.each(
    ["@missing", "@sample:2", "@missing:1:" <> v1.to_string(first.0)],
    fn(code) {
      let #(output, sandbox) =
        check.execute(source.Code(code), helpers.config)
        |> helpers.run(sandbox)
      assert Error("") == output
      let assert [message] = sandbox.stdout
      assert string.contains(message, "missing reference " <> code)
      assert 2 == list.length(sandbox.network_state)
    },
  )
}

pub fn check_verifies_fetched_content_hash_test() {
  let expected = module("1")
  let wrong = module("\"wrong content\"")
  let sandbox = hub(helpers.sandbox(), [], [#(expected.0, wrong.1)])
  let #(output, sandbox) =
    check.execute(source.Code("#" <> v1.to_string(expected.0)), helpers.config)
    |> helpers.run(sandbox)
  assert Error("") == output
  let assert [message] = sandbox.stdout
  assert string.contains(message, "missing reference")
}

pub fn check_does_not_evaluate_fetched_module_initializers_test() {
  let dependency = module("let _ = perform StandardOut(\"do not run\") 42")
  let sandbox = hub(helpers.sandbox(), [], [dependency])
  let #(output, sandbox) =
    check.execute(
      source.Code("#" <> v1.to_string(dependency.0)),
      helpers.config,
    )
    |> helpers.run(sandbox)
  assert Ok(0) == output
  assert ["Integer"] == sandbox.stdout
}

pub fn check_reports_type_errors_in_unevaluated_dependency_code_test() {
  let dependency = module("(_) -> { missing }")
  let parent = module("let unused = #" <> v1.to_string(dependency.0) <> " 42")
  let sandbox = hub(helpers.sandbox(), [], [dependency, parent])
  let #(output, sandbox) =
    check.execute(source.Code("#" <> v1.to_string(parent.0)), helpers.config)
    |> helpers.run(sandbox)
  assert Error("") == output
  let assert [message] = sandbox.stdout
  assert string.contains(message, "missing variable 'missing'")
}

pub fn check_stops_recursive_package_dependencies_test() {
  let dependency = module("@recursive")
  let sandbox =
    hub(helpers.sandbox(), [release("recursive", 1, 1, dependency.0)], [
      dependency,
    ])
  let #(output, sandbox) =
    check.execute(source.Code("@recursive"), helpers.config)
    |> helpers.run(sandbox)
  assert Error("") == output
  let assert [message] = sandbox.stdout
  assert string.contains(message, "missing reference @recursive")
  assert 3 == list.length(sandbox.network_state)
}

pub fn check_hub_imports_do_not_resolve_against_callers_directory_test() {
  let dependency = module("import \"./local.eyg\"")
  let sandbox =
    helpers.sandbox()
    |> helpers.with_file("/local.eyg", "1")
    |> hub([], [dependency])
  let #(output, sandbox) =
    check.execute(
      source.Code("#" <> v1.to_string(dependency.0)),
      helpers.config,
    )
    |> helpers.run(sandbox)
  assert Error("") == output
  let assert [message] = sandbox.stdout
  assert string.contains(message, "missing reference")
}

pub fn check_handles_failed_package_pulls_test() {
  let sandbox =
    helpers.sandbox()
    |> helpers.save_and_return(response.new(503) |> response.set_body(<<>>))
  let #(output, sandbox) =
    check.execute(source.Code("@missing"), helpers.config)
    |> helpers.run(sandbox)
  assert Error("") == output
  let assert [message] = sandbox.stdout
  assert string.contains(message, "missing reference @missing")
  assert 4 == list.length(sandbox.network_state)
}
