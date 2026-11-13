import cloud/beam/execute
import eyg/hub/cache
import eyg/interpreter/value as v
import gleam/erlang/process
import gleam/option.{Some}
import ogre/origin

pub fn state() {
  let assert Ok(origin) = origin.from_string_strict("https://eyg.run")
  execute.State(origin:, cache: cache.ready(), root: option.None)
}

/// Evaluate EYG source to a value, for building policies in tests.
pub fn evaluate(code) {
  let host = execute.Host(post: fn(_) { Error("no posting") })
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
    execute.Host(post: fn(text) {
      process.send(posts, text)
      Ok("m1")
    })
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
  assert result == Error("Relative import of ./x.eyg is not available")
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
  assert result == Error("Relative import of ./index.eyg is not available")
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
