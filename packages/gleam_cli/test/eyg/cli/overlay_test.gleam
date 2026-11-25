import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import eyg/cli/check
import eyg/cli/helpers
import eyg/cli/overlay
import eyg/interpreter/value
import gleam/list
import gleam/option.{Some}
import loam/sandbox
import loam/system
import touch_grass/harness/computer
import touch_grass/interface
import touch_grass/policy
import touch_grass/source

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

pub fn type_check_halts_run_test() {
  let input =
    source.Code(
      "{
  llm: {provider: Mistral({api_key: \"misty_secret\"}), model: \"le-chonk\"},
  policy: {},
  context: {}
}",
    )
  let assert #(sandbox.Returned(#(Ok(session), state)), _) =
    overlay.setup(input, helpers.config, [], [], helpers.state())
    |> sandbox.run(sandbox.sandbox())
  let code = "(_) -> { !int_add(1, \"2\") }"
  let assert system.Done(#(Error(reason), _, _)) =
    overlay.check_and_execute(session, code, state)
  echo reason
}

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

fn filesystem_session(record_gate, path_gate) {
  let rules = [
    #("ReadFile", policy.PolicyField("read_file")),
    #("WriteFile", policy.PolicyField("write_file")),
    #("AppendFile", policy.PolicyField("append_file")),
    #("DeleteFile", policy.PolicyField("delete_file")),
    #("MakeDirectory", policy.PolicyField("make_directory")),
    #("ReadDirectory", policy.PolicyField("read_directory")),
  ]
  let code = "let record_gate = " <> record_gate <> "
let path_gate = " <> path_gate <> "
{
  llm: {provider: Mistral({api_key: \"misty_secret\"}), model: \"le-chonk\"},
  policy: {
    read_file: record_gate, write_file: record_gate, append_file: record_gate,
    delete_file: path_gate, make_directory: path_gate, read_directory: path_gate
  },
  context: {read: (path) -> {
    perform ReadFile({path, offset: 0, limit: 100})
  }}
}"
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_cwd("/project/work")
    |> sandbox.with_file("/project/lib/agent.eyg", code)
  let assert #(sandbox.Returned(#(Ok(session), state)), sandbox) =
    overlay.setup(
      source.File("/project/lib/agent.eyg"),
      helpers.config,
      computer.effects() |> interface.take(list.map(rules, fn(rule) { rule.0 })),
      rules,
      helpers.state(),
    )
    |> sandbox.run(sandbox)
  #(session, state, sandbox)
}

pub fn filesystem_policies_receive_absolute_paths_test() {
  let #(session, state, sandbox) =
    filesystem_session(
      "(lift) -> { Mock(Error(lift.path)) }",
      "(path) -> { Mock(Error(path)) }",
    )
  use path <- list.each([
    "./sub/../target",
    "../work/target",
    "/project/work/./target",
  ])
  let path = "\"" <> path <> "\""
  use code <- list.each([
    "perform ReadFile({path: " <> path <> ", offset: 7, limit: 11})",
    "perform WriteFile({path: "
      <> path
      <> ", contents: !string_to_binary(\"payload\")})",
    "perform AppendFile({path: "
      <> path
      <> ", contents: !string_to_binary(\"payload\")})",
    "perform DeleteFile(" <> path <> ")",
    "perform MakeDirectory(" <> path <> ")",
    "perform ReadDirectory(" <> path <> ")",
  ])
  let assert #(
    sandbox.Returned(#(
      Ok(#(Some(value.Tagged("Error", value.String(path))), _)),
      _,
      [],
    )),
    _,
  ) =
    overlay.check_and_execute(session, code, state)
    |> sandbox.run(sandbox)
  assert path == "/project/work/target"
}

pub fn filesystem_policies_resolve_paths_from_source_test() {
  let #(session, state, sandbox) =
    filesystem_session(
      "(lift) -> { Mock(Error(lift.path)) }",
      "(path) -> { Mock(Error(path)) }",
    )
  let assert #(
    sandbox.Returned(#(
      Ok(#(Some(value.Tagged("Error", value.String(path))), _)),
      _,
      [],
    )),
    _,
  ) =
    overlay.check_and_execute(
      session,
      "context.read(\"./sub/../target\")",
      state,
    )
    |> sandbox.run(sandbox)
  assert path == "/project/lib/target"
}

pub fn invalid_filesystem_paths_return_an_effect_error_test() {
  let #(session, state, sandbox) =
    filesystem_session(
      "(lift) -> { Mock(Error(lift.path)) }",
      "(path) -> { Mock(Error(path)) }",
    )
  let assert #(
    sandbox.Returned(#(
      Ok(#(Some(value.Tagged("Error", value.String(reason))), _)),
      _,
      [],
    )),
    _,
  ) =
    overlay.check_and_execute(
      session,
      "perform ReadFile({path: \"../../../target\", offset: 0, limit: 1})",
      state,
    )
    |> sandbox.run(sandbox)
  assert reason == "invalid path"
}
