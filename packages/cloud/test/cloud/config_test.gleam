import cloud/beam/execute
import cloud/config
import cloud/execute_test
import cloud/handler
import cloud/test_helpers
import cloud/work
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/string
import simplifile

pub fn invalid_source_is_rejected_before_configuration_effects_test() {
  let reads = process.new_subject()
  let source =
    "let _ = perform Secret(\"token\") {llm: {}, channel: (_) -> { {on_input: (_) -> { [] }, channel_shell: {post: (_) -> { Mock(42) }, ..cloud.mock_all}} }}"
  let assert Error(_) =
    config.load_source("workspace.eyg", source, test_helpers.state(), fn(name) {
      process.send(reads, name)
      Ok("secret")
    })
  assert process.receive(reads, 0) == Error(Nil)
}

pub fn loader_rechecks_changed_imports_before_running_configuration_test() {
  let directory = test_helpers.directory()
  let assert Ok(_) = simplifile.create_directory_all(directory)
  let file = directory <> "/workspace.eyg"
  let dependency = directory <> "/handler.eyg"
  let assert Ok(_) = simplifile.write(dependency, "(_) -> { [] }")
  let source =
    "let on_input = import \"./handler.eyg\" let _ = perform Secret(\"token\") {llm: {provider: Ollama({origin: \"http://localhost\", api_key: None({})}), model: \"test\"}, channel: (_) -> { {on_input, channel_shell: cloud.mock_all} }}"
  let assert Ok(_) = simplifile.write(file, source)
  let reads = process.new_subject()
  let load =
    config.loader(file, test_helpers.state(), fn(name) {
      process.send(reads, name)
      Ok("secret")
    })
  let assert Ok(_) = load()
  assert process.receive(reads, 0) == Ok("token")
  let assert Ok(_) = simplifile.write(dependency, "(_) -> { 42 }")
  let assert Error(_) = load()
  assert process.receive(reads, 0) == Error(Nil)
  let assert Ok(_) = simplifile.delete(directory)
}

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
  assert string.contains(reason, "on_input")
}

pub fn bad_handlers_and_policies_are_rejected_on_admission_test() {
  list.each(
    [
      "channel_shell: cloud.mock_all",
      "on_input: (_) -> { 42 }, channel_shell: cloud.mock_all",
      "on_input: (_) -> { [Post({thread: None({}), text: 42})] }, channel_shell: cloud.mock_all",
      "on_input: (_) -> { let _ = perform Post(\"side effect\") [] }, channel_shell: cloud.mock_all",
      "on_input: (_) -> { [] }, channel_shell: {}",
      "on_input: (_) -> { [] }, channel_shell: {post: (_) -> { Mock(42) }, ..cloud.mock_all}",
    ],
    fn(fields) {
      let source =
        "{llm: {provider: Ollama({origin: \"http://localhost\", api_key: None({})}), model: \"test\"}, channel: (_) -> { {"
        <> fields
        <> "} }}"
      let assert Error(_) =
        config.load_source("workspace.eyg", source, test_helpers.state(), fn(_) {
          Error("no secrets")
        })
    },
  )
}

pub fn callback_field_can_be_selected_and_destructured_test() {
  assert execute_test.evaluate(
      "let config = {on_input: (event) -> { event }} let {on_input} = config on_input(config.on_input(42))",
    )
    == v.Integer(42)
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
