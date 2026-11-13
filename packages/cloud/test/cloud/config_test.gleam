import cloud/beam/execute
import cloud/config
import cloud/execute_test
import cloud/handler
import cloud/test_helpers
import cloud/work
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import simplifile

fn load() {
  let assert Ok(workspace) =
    config.load("test/fixtures/workspace.eyg", test_helpers.state(), fn(_) {
      Error("no secrets")
    })
  workspace
}

pub fn load_workspace_test() {
  let workspace = load()
  assert workspace.llm.model == "test-model"
  assert workspace.readme == "The test workspace."
}

pub fn channel_shell_test() {
  let workspace = load()
  let info =
    config.ChannelInfo(
      platform: "chat",
      id: "C1",
      name: "general",
      input_type: t.record([#("text", t.String)]),
    )
  let assert Ok(config.Channel(shell:, readme:, ..)) =
    config.channel(workspace, info)
  assert readme == "Be helpful."
  assert list.contains(dict.keys(shell), "Fetch")
}

pub fn restricted_channel_test() {
  let workspace = load()
  let info =
    config.ChannelInfo(
      platform: "chat",
      id: "C2",
      name: "random",
      input_type: t.record([#("text", t.String)]),
    )
  let assert Ok(config.Channel(shell:, readme:, ..)) =
    config.channel(workspace, info)
  assert readme == ""
  assert list.sort(dict.keys(shell), string.compare)
    == list.sort(dict.keys(execute.unrestricted()), string.compare)
}

pub fn checked_native_input_becomes_work_test() {
  let workspace = load()
  let info =
    config.ChannelInfo("chat", "C1", "general", t.record([#("text", t.String)]))
  let assert Ok(channel) = config.channel(workspace, info)
  let input = v.Record(dict.from_list([#("text", v.String("native input"))]))
  assert handler.run(channel.handle, input, workspace.state)
    == Ok([work.Post(option.None, "native input")])
}

pub fn configured_handler_is_checked_against_the_plugin_type_test() {
  let workspace = load()
  let info =
    config.ChannelInfo(
      "chat",
      "C1",
      "general",
      t.record([#("ticket", t.String)]),
    )
  let assert Error(reason) = config.channel(workspace, info)
  assert string.contains(reason, "handle")
}

pub fn bad_handlers_and_policies_are_rejected_on_admission_test() {
  let workspace = load()
  let info =
    config.ChannelInfo("chat", "C1", "general", t.record([#("text", t.String)]))
  list.each(
    [
      "channel_shell: cloud.reject_all",
      "handle: (_) -> { 42 }, channel_shell: cloud.reject_all",
      "handle: (_) -> { [Post({thread: None({}), text: 42})] }, channel_shell: cloud.reject_all",
      "handle: (_) -> { let _ = perform Post(\"side effect\") [] }, channel_shell: cloud.reject_all",
      "handle: (_) -> { [] }, channel_shell: {}",
      "handle: (_) -> { [] }, channel_shell: {post: (_) -> { Mock(42) }, ..cloud.reject_all}",
    ],
    fn(fields) {
      let channel = execute_test.evaluate("(_) -> { {" <> fields <> "} }")
      let assert Error(_) =
        config.channel(config.Workspace(..workspace, channel:), info)
    },
  )
}

pub fn keyword_field_can_be_selected_and_destructured_test() {
  assert execute_test.evaluate(
      "let config = {handle: (event) -> { event }} let {handle: on_input} = config on_input(config.handle(42))",
    )
    == v.Integer(42)
}

pub fn secrets_are_placeholders_in_channels_test() {
  let assert Ok(workspace) =
    config.load(
      "test/fixtures/secrets_workspace.eyg",
      test_helpers.state(),
      fn(name) {
        case name {
          "GITHUB_TOKEN" -> Ok("ghp_real")
          _ -> Error("no secret")
        }
      },
    )
  let info =
    config.ChannelInfo(
      platform: "chat",
      id: "C1",
      name: "general",
      input_type: t.record([#("text", t.String)]),
    )
  let assert Ok(config.Channel(shell:, ..)) = config.channel(workspace, info)
  let host =
    execute.channel_host(
      fn(_) { Ok("m") },
      execute.no_files(),
      execute.no_triggers(),
      execute.no_schedules(),
      execute.no_artifacts(),
    )
  let #(execute.Run(result:, ..), _) =
    execute.run(
      "perform Env(\"GITHUB_TOKEN\")",
      [],
      shell,
      host,
      test_helpers.state(),
    )
  let digest =
    crypto.hash(crypto.Sha256, <<"ghp_real":utf8>>)
    |> bit_array.base16_encode
    |> string.lowercase
  assert result == Ok(Some(v.some(v.String("eyg-secret-" <> digest))))
}

pub fn channels_can_choose_a_model_test() {
  let workspace = load()
  let general =
    config.ChannelInfo(
      platform: "chat",
      id: "C1",
      name: "general",
      input_type: t.record([#("text", t.String)]),
    )
  let assert Ok(config.Channel(llm:, ..)) = config.channel(workspace, general)
  assert llm.model == "test-model"
  let random =
    config.ChannelInfo(
      platform: "chat",
      id: "C3",
      name: "random",
      input_type: t.record([#("text", t.String)]),
    )
  let assert Ok(config.Channel(llm:, ..)) = config.channel(workspace, random)
  assert llm.model == "small"
}

pub fn dataclip_policies_are_checked_when_workspace_source_is_loaded_test() {
  let file = "test/fixtures/database_workspace.eyg"
  let assert Ok(source) = simplifile.read(file)
  let state = test_helpers.state()
  let secret = fn(_) { Error("no secrets") }
  let assert Ok(_) = config.load_source(file, source, state, secret)
  list.each(
    [
      "{}",
      "{sqlite: (_) -> { Mock(42) }, ..cloud.reject_all}",
      "{sqlite: (input) -> { let _ = perform Leak(input) Pass(input) }, ..cloud.reject_all}",
    ],
    fn(policy) {
      let candidate =
        string.replace(source, "shell: notes", "shell: " <> policy)
      assert candidate != source
      let assert Error(reason) =
        config.load_source(file, candidate, state, secret)
      assert string.contains(reason, "dataclip count_notes")
    },
  )
}
