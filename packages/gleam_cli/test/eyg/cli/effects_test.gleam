import eyg/cli/helpers
import eyg/cli/run
import eyg/cli/script
import glasshouse/archive
import glasshouse/rerun
import glasshouse/run as recorded
import glasshouse/session
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import loam/sandbox
import loam/sandbox/fs
import loam/source

const gates =
  "{acquire: Pass, mount: Pass, append_file: Pass, create_key: Pass, cwd: Pass, delete_file: Pass, env: Pass, exit: Pass, fetch: Pass, flip: Pass, make_directory: Pass, now: Pass, random: Pass, read_directory: Pass, read_file: Pass, sleep: Pass, standard_error: Pass, standard_in: Pass, standard_out: Pass, write_file: Pass}"

fn execute(code) {
  let assert #(sandbox.Returned(result), sandbox) =
    run.execute(source.Code(code), helpers.config)
    |> sandbox.run(
      sandbox.sandbox()
      |> sandbox.with_cwd("/project")
      |> sandbox.with_random_values([1]),
    )
  #(result, sandbox)
}

pub fn type_check_effect_returns_types_and_errors_test() {
  let #(result, sandbox) =
    execute(
      "let _ = perform StandardOut(perform TypeCheck(\"{api_key: \\\"x\\\"}\"))",
    )
  // TypeCheck returns a Result, so passing it as text must fail at runtime.
  let assert Error(_) = result
  assert sandbox.stdout == []
  let #(result, sandbox) =
    execute(
      "match perform TypeCheck(\"{api_key: \\\"x\\\"}\") { Ok(type_) -> { perform StandardOut(type_) } Error(reason) -> { perform Abort(reason) } }",
    )
  assert result == Ok(0)
  assert sandbox.stdout == ["{api_key: String}"]
  list.each(["!int_add(1, \"two\")", "let ="], fn(code) {
    let code =
      "match perform TypeCheck("
      <> quote(code)
      <> ") { Ok(_) -> { perform Abort(\"accepted\") } Error(_) -> { 0 } }"
    assert execute(code).0 == Ok(0)
  })
}

pub fn type_check_imports_resolve_from_invocation_directory_test() {
  let code =
    "match perform TypeCheck(\"import \\\"./value.eyg\\\"\") { Ok(type_) -> { perform StandardOut(type_) } Error(reason) -> { perform Abort(reason) } }"
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    run.execute(source.Code(code), helpers.config)
    |> sandbox.run(
      sandbox.sandbox()
      |> sandbox.with_cwd("/project")
      |> sandbox.with_file("/project/value.eyg", "42"),
    )
  assert sandbox.stdout == ["Integer"]
}

fn overlay_error(context) {
  let code =
    "match perform Overlay({llm: 1, policy: {}, context: "
    <> context
    <> "}) { Ok(_) -> { perform Abort(\"started\") } Error(reason) -> { perform StandardOut(reason) } }"
  let #(result, sandbox) = execute(code)
  assert result == Ok(0)
  let assert [reason] = sandbox.stdout
  reason
}

pub fn invalid_config_and_context_fail_before_taking_input_test() {
  assert string.starts_with(
    overlay_error("{}"),
    "error: invalid overlay config",
  )
  assert string.starts_with(
    overlay_error("{add: (x) -> { !int_add(x, \"one\") }}"),
    "error: invalid context:",
  )
  assert string.starts_with(
    overlay_error("{add: (x) -> { !int_add(x, 1) }}"),
    "error: invalid overlay config",
  )
}

pub fn script_resumes_after_an_empty_recorded_conversation_test() {
  let secret = "long-fake-model-credential"
  let code =
    "{script: (_) -> { let key = "
    <> quote(secret)
    <> " let context = {readme: \"test\", token: (_) -> { key }} match perform Overlay({llm: {provider: Mistral({api_key: key}), model: \"fixture\"}, policy: "
    <> gates
    <> ", context}) { Ok(_) -> { 7 } Error(reason) -> { let _ = perform StandardOut(reason) 1 } } } }"
  let assert #(sandbox.Returned(Ok(7)), sandbox) =
    script.execute(source.Code(code), [], helpers.config)
    |> sandbox.run(
      sandbox.sandbox()
      |> sandbox.with_cwd("/project")
      |> sandbox.with_random_values([1]),
    )
  let assert Ok(text) =
    fs.read(
      sandbox.file_system,
      "/project/.eyg/traces/19700101T000000-0001.json",
    )
  assert !string.contains(text, secret)
  let assert Ok(archive) = archive.from_string(text)
  assert archive.missing(archive) == []
  assert [recorded.Config]
    == archive.session.events
    |> list.filter_map(fn(event) {
      case event {
        session.Execution(run) -> Ok(run.kind)
        _ -> Error(Nil)
      }
    })
  assert list.all(rerun.session(archive.session, archive.store), fn(run) {
    run.problem == None
  })
}

pub fn captured_lazy_imports_are_pinned_and_replayable_test() {
  let code =
    "let context = import \"./lib/context.eyg\" match perform Overlay({llm: {provider: Mistral({api_key: \"fake-long-model-key\"}), model: \"fixture\"}, policy: "
    <> gates
    <> ", context}) { Ok(_) -> { 0 } Error(reason) -> { perform Abort(reason) } }"
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    run.execute(source.Code(code), helpers.config)
    |> sandbox.run(
      sandbox.sandbox()
      |> sandbox.with_cwd("/project")
      |> sandbox.with_random_values([1])
      |> sandbox.with_file(
        "/project/lib/context.eyg",
        "{readme: \"lazy import\", number: (_) -> { import \"./number.eyg\" }}",
      )
      |> sandbox.with_file("/project/lib/number.eyg", "42"),
    )
  let assert Ok(text) =
    fs.read(
      sandbox.file_system,
      "/project/.eyg/traces/19700101T000000-0001.json",
    )
  let assert Ok(saved) = archive.from_string(text)
  assert archive.missing(saved) == []
  assert list.all(rerun.session(saved.session, saved.store), fn(report) {
    report.problem == None
  })
}

fn quote(text) {
  json.to_string(json.string(text))
}
