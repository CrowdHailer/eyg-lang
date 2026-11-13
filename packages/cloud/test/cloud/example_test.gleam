//// The example workspace in `examples/cloud` loads and configures its channels.

import cloud/beam/execute
import cloud/config
import cloud/database
import cloud/discord/events as discord
import cloud/execute_test
import cloud/plugins/chat_input
import cloud/plugins/whatsapp
import cloud/slack/events as slack
import cloud/test_helpers
import cloud/trigger
import eyg/interpreter/capture
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option
import overlay/policy
import simplifile
import touch_grass/sqlite

fn load() {
  let assert Ok(workspace) =
    config.load(
      "../../examples/cloud/workspace.eyg",
      test_helpers.state(),
      fn(name) { Ok("value of " <> name) },
    )
  workspace
}

fn channel(name) {
  let assert Ok(channel) =
    config.channel(
      load(),
      config.ChannelInfo("chat", "C1", name, chat_input.input_type()),
    )
  channel
}

pub fn example_workspace_test() {
  let workspace = load()
  assert workspace.llm.model == "glm-5.3"
  let assert [config.Cron(name: "standup", ..)] = workspace.crons
}

pub fn links_summarises_and_saves_links_test() {
  let names = list.map(channel("links").triggers, fn(t) { t.name })
  assert names == ["summarise-links", "save-links"]
  assert list.contains(dict.keys(channel("links").shell), "SQLite")
}

pub fn recent_links_dataclip_test() {
  let assert [dataclip] = load().dataclips
  assert dataclip.name == "recent_links"
  assert dict.size(dataclip.shell) == list.length(execute.harness())
  let assert #(policy.Unavailable, _) =
    execute.decide(
      dataclip.shell,
      "Post",
      v.String("hello"),
      #(0, 0),
      test_helpers.state(),
    )
}

pub fn other_channels_are_offline_test() {
  let keys = dict.keys(channel("random").shell)
  assert list.contains(keys, "Fetch")
  assert list.contains(keys, "WriteFile")
  assert list.contains(dict.keys(channel("general").shell), "Env")
}

pub fn named_factories_check_handlers_for_each_native_platform_test() {
  let workspace = load()
  list.each(
    [
      #("chat", chat_input.input_type()),
      #("slack", slack.input_type()),
      #("discord", discord.input_type()),
      #("whatsapp", whatsapp.input_type()),
    ],
    fn(platform) {
      list.each(["general", "links", "random"], fn(name) {
        let assert Ok(_) =
          config.channel(
            workspace,
            config.ChannelInfo(platform.0, "C1", name, platform.1),
          )
      })
    },
  )
}

pub fn link_summaries_project_each_platforms_native_reaction_test() {
  let workspace = load()
  let channel = channel("links")
  let assert [trigger, _save] = channel.triggers
  let assert trigger.Function(script) = trigger.script
  let tasks = process.new_subject()
  let host =
    execute.channel_host(
      fn(_) { Ok("posted") },
      execute.no_files(),
      execute.no_triggers(),
      execute.no_schedules(),
      execute.no_artifacts(),
    )
  let host =
    execute.Host(..host, subagent: fn(task, _trace, state) {
      process.send(tasks, task)
      #(Ok("done"), state)
    })
  list.each(
    [
      #(
        "ChatReacted({message: {text: \"chat link\"}, emoji: \"books\"})",
        "chat link",
      ),
      #(
        "SlackReaction({message: {text: \"slack link\"}, reaction: \"books\"})",
        "slack link",
      ),
      #(
        "DiscordReaction({message: {content: \"discord link\"}, emoji: \"📚\"})",
        "discord link",
      ),
      #(
        "WhatsAppMessage({message: {content: Reaction({emoji: \"📚\"})}, referenced: Some({content: Text(\"whatsapp link\")})})",
        "whatsapp link",
      ),
    ],
    fn(example) {
      let event = capture.capture(execute_test.evaluate(example.0), #(0, 0))
      let #(matched, _) =
        execute.run_expression(
          #(ir.Apply(trigger.pattern, event), #(0, 0)),
          [],
          channel.shell,
          host,
          workspace.state,
        )
      assert matched.result == Ok(option.Some(v.true()))
      let #(run, _) =
        execute.run_expression(
          #(ir.Apply(script, event), #(0, 0)),
          [],
          channel.shell,
          host,
          workspace.state,
        )
      let assert Ok(_) = run.result
      assert process.receive(tasks, 0)
        == Ok(
          "Fetch each link in this message and post a two sentence summary of each link. Message: "
          <> example.1,
        )
    },
  )
}

pub fn saved_links_keep_each_platforms_native_fields_test() {
  let workspace = load()
  let channel = channel("links")
  let assert [_, trigger] = channel.triggers
  let assert trigger.Function(script) = trigger.script
  let assert Ok(path) = database.path("build/example_database_test", "links")
  let _ = simplifile.delete(path)
  let host =
    execute.Host(
      ..execute.configuration_host(fn(_) { Error("no secrets") }),
      database: database.path("build/example_database_test", _),
    )
  let examples = [
    "ChatPosted({id: \"chat\", author: {name: \"Alice\"}, text: \"https://chat.test\"})",
    "SlackMessage({message: {ts: \"slack\", user: Some(\"U1\"), text: \"https://slack.test\"}})",
    "DiscordMessage({message: {id: \"discord\", author: {username: \"Bob\"}, content: \"https://discord.test\"}})",
    "WhatsAppMessage({message: {id: \"whatsapp\", from: \"123\", content: Text(\"https://whatsapp.test\")}})",
  ]
  list.each(examples, fn(code) {
    let event = capture.capture(execute_test.evaluate(code), #(0, 0))
    let #(matched, _) =
      execute.run_expression(
        #(ir.Apply(trigger.pattern, event), #(0, 0)),
        [],
        channel.shell,
        host,
        workspace.state,
      )
    assert matched.result == Ok(option.Some(v.true()))
    let #(run, _) =
      execute.run_expression(
        #(ir.Apply(script, event), #(0, 0)),
        [],
        channel.shell,
        host,
        workspace.state,
      )
    let assert Ok(option.Some(v.Tagged("Ok", _))) = run.result
  })
  assert database.run(
      path,
      "SELECT id, author, text FROM links ORDER BY id",
      [],
    )
    == Ok([
      [
        sqlite.Text("chat"),
        sqlite.Text("Alice"),
        sqlite.Text("https://chat.test"),
      ],
      [
        sqlite.Text("discord"),
        sqlite.Text("Bob"),
        sqlite.Text("https://discord.test"),
      ],
      [
        sqlite.Text("slack"),
        sqlite.Text("U1"),
        sqlite.Text("https://slack.test"),
      ],
      [
        sqlite.Text("whatsapp"),
        sqlite.Text("123"),
        sqlite.Text("https://whatsapp.test"),
      ],
    ])
}
