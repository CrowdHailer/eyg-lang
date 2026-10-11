import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import eyg/cli/check
import eyg/cli/helpers
import eyg/cli/overlay
import eyg/interpreter/value
import gleam/option.{Some}
import gleam/string
import loam/sandbox
import loam/source
import loam/system
import overlay/policy
import touch_grass
import touch_grass/file_system/read_file
import touch_grass/harness/computer

// const allow_policy =
//   "
// {
//   llm: {provider: Mistral({api_key: \"misty_secret\"}), model: \"le-chonk\"},
//   policy: {
//     append_file: Pass,
//     create_key: Pass,
//     cwd: Pass,
//     delete_file: Pass,
//     env: Pass,
//     fetch: Pass,
//     make_directory: Pass,
//     now: Pass,
//     read_directory: Pass,
//     read_file: Pass,
//     sign: Pass,
//     sleep: Pass,
//     standard_error: Pass,
//     standard_in: Pass,
//     standard_out: Pass,
//     write_file: Pass,
//   },
//   context: {}
// }"

pub fn setup_generalises_context_types_test() {
  let input =
    source.Code(
      "{
  llm: {provider: Mistral({api_key: \"misty_secret\"}), model: \"le-chonk\"},
  policy: {},
  context: {items: [], identity: (x) -> { x }}
}",
    )
  let assert #(sandbox.Returned(#(Ok(session), state)), _) =
    overlay.setup(input, helpers.config, [], [], helpers.state())
    |> sandbox.run(sandbox.sandbox())

  let assert Ok(source) =
    source.parse_input(
      "{integer: context.identity(1), string: context.identity(\"hello\")}",
      source.Stdin,
    )
  let base = infer.pure()
  let context =
    infer.Context(..base, env: [#("context", session.context.type_)])
  let assert system.Done(#(_, type_, [], _)) =
    check.check_from(source, session.cwd, context, state)
  assert type_ == t.record([#("integer", t.Integer), #("string", t.String)])
}

pub fn read_file_policy_is_used_for_imports_test() {
  // let cwd = "/user/oliver"
  let sandbox = sandbox.sandbox()
  let policy =
    "
{
  llm: {provider: Mistral({api_key: \"misty_secret\"}), model: \"le-chonk\"},
  policy: {read_file: (lift) -> {
    match !equal(lift.path, \"/user/oliver/secret.eyg\") {
      True(_) -> { Mock(Error(\"denied\")) }
      False(_) -> { Pass(lift) }
    }
  }},
  context: {}
}"
  let input = source.Code(policy)
  let assert #(sandbox.Returned(#(Ok(session), state)), _sandbox) =
    overlay.setup(
      input,
      helpers.config,
      [touch_grass.read_file() |> touch_grass.map(computer.ReadFile)],
      [#(read_file.label, policy.PolicyField("read_file"))],
      helpers.state(),
    )
    |> sandbox.run(sandbox)

  // absolute file paths are handled correctly
  let code =
    "perform ReadFile({path: \"/user/oliver/fine.eyg\", offset: 0, limit: 100})"
  let assert system.ReadFileRange(path:, offset:, limit:, resume:) =
    overlay.check_and_execute(session, code, state)
  assert "/user/oliver/fine.eyg" == path
  assert 0 == offset
  assert 100 == limit
  let assert system.Done(#(Ok(return), _state, [])) = resume(Ok(<<"hi">>))
  let assert #(Some(value.Tagged("Ok", value.Binary(<<"hi">>))), _) = return

  let code =
    "perform ReadFile({path: \"/user/oliver/secret.eyg\", offset: 0, limit: 100})"
  let assert system.Done(#(Ok(return), _state, [])) =
    overlay.check_and_execute(session, code, state)
  let assert #(Some(value.Tagged("Error", value.String("denied"))), _) = return

  // imports are resolved to be absolute
  let code = "import \"/user/oliver/fine.eyg\""
  let assert system.ReadFile("/user/oliver/fine.eyg", resume) =
    overlay.check_and_execute(session, code, state)
  let assert system.Done(#(Ok(return), _state, [])) = resume(Ok("3"))
  let assert #(Some(value.Integer(3)), _) = return

  let code = "import \"/user/oliver/secret.eyg\""
  let assert system.Done(#(Error(reason), _state, _)) =
    overlay.check_and_execute(session, code, state)
  assert string.contains(reason, "denied by policy")
}
