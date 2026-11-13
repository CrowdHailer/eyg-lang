import cloud/beam/execute
import cloud/test_helpers
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/erlang/process
import gleam/option.{Some}
import gleam/result

pub fn state() {
  test_helpers.state()
}

/// Evaluate EYG source to a value, for building policies in tests.
pub fn evaluate(code) {
  let host =
    execute.channel_host(
      fn(_) { Error("no posting") },
      execute.no_files(),
      execute.no_triggers(),
      execute.no_schedules(),
      execute.no_artifacts(),
    )
  let #(execute.Run(result:, ..), _) =
    execute.run(code, [], execute.unrestricted(), host, state())
  let assert Ok(Some(value)) = result
  value
}

fn policy(code) {
  let assert Ok(policy) = execute.decode_policy(evaluate(code), state())
  policy
}

fn recording_host() {
  let posts = process.new_subject()
  let host =
    execute.channel_host(
      fn(text) {
        process.send(posts, text)
        Ok("m1")
      },
      execute.no_files(),
      execute.no_triggers(),
      execute.no_schedules(),
      execute.no_artifacts(),
    )
  #(host, posts)
}

pub fn allowed_post_test() {
  let #(host, posts) = recording_host()
  let policy = policy("{post: (text) -> { Pass(text) }, ..cloud.reject_all}")
  let #(execute.Run(result:, ..), _) =
    execute.run("perform Post(\"hi\")", [], policy, host, state())
  assert result == Ok(Some(v.ok(v.String("m1"))))
  assert process.receive(posts, 0) == Ok("hi")
}

pub fn gate_can_change_input_test() {
  let #(host, posts) = recording_host()
  let policy =
    policy(
      "{post: (text) -> { Pass(!string_append(\"bot: \", text)) }, ..cloud.reject_all}",
    )
  let _ = execute.run("perform Post(\"hi\")", [], policy, host, state())
  assert process.receive(posts, 0) == Ok("bot: hi")
}

pub fn gate_can_mock_test() {
  let #(host, posts) = recording_host()
  let policy =
    policy("{post: (_) -> { Mock(Error(\"muted\")) }, ..cloud.reject_all}")
  let #(execute.Run(result:, ..), _) =
    execute.run("perform Post(\"hi\")", [], policy, host, state())
  assert result == Ok(Some(v.error(v.String("muted"))))
  assert process.receive(posts, 0) == Error(Nil)
}

pub fn reject_all_makes_effects_unavailable_test() {
  let #(host, _posts) = recording_host()
  let policy = policy("cloud.reject_all")
  let #(execute.Run(result:, ..), _) =
    execute.run("perform Post(\"hi\")", [], policy, host, state())
  assert result == Error("Effect Post is not allowed by policy")
}

pub fn unchecked_effects_need_no_gate_test() {
  let #(host, _posts) = recording_host()
  let #(execute.Run(result:, ..), _) =
    execute.run(
      "perform DecodeJSON(!string_to_binary(\"1\"))",
      [],
      policy("cloud.reject_all"),
      host,
      state(),
    )
  let assert Ok(Some(_)) = result
}

pub fn output_is_captured_test() {
  let #(host, _posts) = recording_host()
  let policy =
    policy("{standard_out: (text) -> { Pass(text) }, ..cloud.reject_all}")
  let #(execute.Run(output:, ..), _) =
    execute.run(
      "let _ = perform StandardOut(\"a\")\nperform StandardOut(\"b\")",
      [],
      policy,
      host,
      state(),
    )
  assert output == [execute.StandardOut("b"), execute.StandardOut("a")]
}

pub fn relative_import_is_unavailable_without_session_files_test() {
  let #(host, _posts) = recording_host()
  let #(execute.Run(result:, ..), _) =
    execute.run("import \"./x.eyg\"", [], execute.unrestricted(), host, state())
  assert result == Error("There is no file system")
}

pub fn script_import_cannot_read_a_configured_host_root_test() {
  let #(host, _) = recording_host()
  let state = execute.State(..state(), root: Some("../../eyg_packages/overlay"))
  let #(execute.Run(result:, ..), _) =
    execute.run(
      "import \"./index.eyg\"",
      [],
      execute.unrestricted(),
      host,
      state,
    )
  assert result == Error("There is no file system")
}

pub fn missing_or_invalid_policy_gates_are_rejected_when_set_test() {
  let assert Error(_) = execute.decode_policy(evaluate("{}"), state())
  let assert Error(_) = execute.decode_policy(evaluate("{post: 1}"), state())
  let assert Error(_) =
    execute.decode_policy(
      evaluate("{post: (_) -> { Mock(42) }, ..cloud.reject_all}"),
      state(),
    )
  let assert Error(_) =
    execute.decode_policy(
      evaluate("{post: (text) -> { perform Post(text) }, ..cloud.reject_all}"),
      state(),
    )
}

pub fn successive_programs_do_not_retain_scope_test() {
  let #(host, _) = recording_host()
  let #(execute.Run(result: first, ..), next) =
    execute.run(
      "let retained = 42\nretained",
      [],
      execute.unrestricted(),
      host,
      state(),
    )
  assert first == Ok(Some(v.Integer(42)))
  let #(execute.Run(result: second, ..), _) =
    execute.run("retained", [], execute.unrestricted(), host, next)
  let assert Error(_) = second
}

pub fn package_reject_all_matches_the_native_platform_contract_test() {
  let state = execute.State(..state(), root: Some("."))
  let #(run, state) =
    execute.run_configuration(
      "import \"../../eyg_packages/cloud/platform.eyg\".reject_all",
      execute.unrestricted(),
      execute.channel_host(
        fn(_) { Error("Configuration cannot post") },
        execute.no_files(),
        execute.no_triggers(),
        execute.no_schedules(),
        execute.no_artifacts(),
      ),
      state,
    )
  let assert Ok(Some(package)) = run.result
  let assert Ok(native) = cast.field("reject_all", Ok, execute.platform())
  let assert Ok(package_fields) = cast.as_record(package)
  let assert Ok(native_fields) = cast.as_record(native)
  assert dict.keys(package_fields) == dict.keys(native_fields)
  let assert Ok(_) = execute.decode_policy(package, state)
}

pub fn configuration_reads_secrets_test() {
  let host = execute.configuration_host(fn(name) { Ok("value of " <> name) })
  let #(execute.Run(result:, ..), _) =
    execute.run_configuration(
      "perform Secret(\"KEY\")",
      execute.configuration(),
      host,
      state(),
    )
  assert result == Ok(Some(v.ok(v.String("value of KEY"))))
}

pub fn channels_cannot_read_secrets_test() {
  let host = execute.configuration_host(fn(_) { Ok("leaked") })
  let shell = policy("cloud.reject_all")
  let #(execute.Run(result:, ..), _) =
    execute.run("perform Secret(\"KEY\")", [], shell, host, state())
  assert result == Error("Effect Secret is not allowed by policy")
}

fn module_host(modules) {
  let #(host, _) = recording_host()
  let modules = dict.from_list(modules)
  let reads = process.new_subject()
  let files =
    execute.Files(..host.files, read: fn(path) {
      process.send(reads, path)
      dict.get(modules, path)
      |> result.replace_error("missing session file " <> path)
    })
  #(execute.Host(..host, files:), reads)
}

pub fn scripts_read_session_files_even_with_a_host_root_test() {
  let #(host, reads) = module_host([#("/etc/passwd", <<"42":utf8>>)])
  let state = execute.State(..state(), root: Some("/"))
  let #(execute.Run(result:, ..), _) =
    execute.run(
      "import \"/etc/passwd\"",
      [],
      execute.unrestricted(),
      host,
      state,
    )
  assert result == Ok(Some(v.Integer(42)))
  assert process.receive(reads, 0) == Ok("/etc/passwd")
}

pub fn import_denial_never_reads_the_file_test() {
  let #(host, reads) = module_host([#("/private.eyg", <<"42":utf8>>)])
  let #(execute.Run(result:, ..), _) =
    execute.run(
      "import \"./private.eyg\"",
      [],
      policy("cloud.reject_all"),
      host,
      state(),
    )
  assert result == Error("Effect ReadFile is not allowed by policy")
  assert process.receive(reads, 0) == Error(Nil)
}

pub fn nested_and_deferred_imports_follow_the_redirected_session_path_test() {
  let #(host, reads) =
    module_host([
      #("/lib/module.eyg", <<"(_) -> { import \"./answer.eyg\" }":utf8>>),
      #("/lib/answer.eyg", <<"42":utf8>>),
    ])
  let shell =
    policy(
      "{read_file: (request) -> { match !equal(request.path, \"/entry.eyg\") { True(_) -> { Pass({path: \"/lib/module.eyg\", ..request}) } False(_) -> { Pass(request) } } }, ..cloud.reject_all}",
    )
  let #(execute.Run(result:, ..), _) =
    execute.run(
      "let module = import \"./entry.eyg\"\nmodule({})",
      [],
      shell,
      host,
      state(),
    )
  assert result == Ok(Some(v.Integer(42)))
  assert process.receive(reads, 0) == Ok("/lib/module.eyg")
  assert process.receive(reads, 0) == Ok("/lib/answer.eyg")
}

pub fn import_mock_returns_a_module_without_reading_test() {
  let #(host, reads) = module_host([])
  let shell =
    policy(
      "{read_file: (_) -> { Mock(Ok(!string_to_binary(\"42\"))) }, ..cloud.reject_all}",
    )
  let #(execute.Run(result:, ..), _) =
    execute.run("import \"./virtual.eyg\"", [], shell, host, state())
  assert result == Ok(Some(v.Integer(42)))
  assert process.receive(reads, 0) == Error(Nil)
}

pub fn cyclic_session_import_fails_without_recursing_forever_test() {
  let #(host, _) =
    module_host([#("/cycle.eyg", <<"import \"./cycle.eyg\"":utf8>>)])
  let #(execute.Run(result:, ..), _) =
    execute.run(
      "import \"./cycle.eyg\"",
      [],
      execute.unrestricted(),
      host,
      state(),
    )
  assert result == Error("Cyclic session import: /cycle.eyg")
}

pub fn import_honours_the_gates_read_range_test() {
  let #(host, reads) = module_host([#("/wrapped.eyg", <<"xx42yy":utf8>>)])
  let shell =
    policy(
      "{read_file: (request) -> { Pass({offset: 2, limit: 2, ..request}) }, ..cloud.reject_all}",
    )
  let #(execute.Run(result:, ..), _) =
    execute.run("import \"/wrapped.eyg\"", [], shell, host, state())
  assert result == Ok(Some(v.Integer(42)))
  assert process.receive(reads, 0) == Ok("/wrapped.eyg")
}
