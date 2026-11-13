//// The example workspace in `examples/cloud` loads and configures its channels.

import cloud/beam/execute
import cloud/config
import cloud/execute_test
import cloud/plugins/chat_input
import cloud/plugins/discord
import cloud/plugins/slack
import cloud/plugins/whatsapp
import cloud/test_helpers
import cloud/trigger
import eyg/interpreter/capture
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option

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

pub fn links_summarises_with_books_test() {
  let assert [trigger] = channel("links").triggers
  assert trigger.name == "summarise-links"
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
  let assert [trigger] = channel.triggers
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
    execute.Host(..host, subagent: fn(task, _trace) {
      process.send(tasks, task)
      Ok("done")
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
