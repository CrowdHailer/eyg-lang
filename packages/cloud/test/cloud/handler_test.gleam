import cloud/config
import cloud/handler
import cloud/plugins/chat_input
import cloud/plugins/discord
import cloud/plugins/example_chat
import cloud/plugins/slack
import cloud/test_helpers
import cloud/work
import gleam/option.{None}
import overlay/check

pub fn example_chat_native_values_and_default_handler_match_the_plugin_type_test() {
  let state = test_helpers.state()
  let assert Ok(workspace) =
    config.load("test/fixtures/chat_workspace.eyg", state, fn(_) {
      Error("no secrets")
    })
  let info =
    config.ChannelInfo("chat", "C1", "general", example_chat.input_type())
  let assert Ok(channel) = config.channel(workspace, info)
  let author = chat_input.Author("U1", "Alice", False)
  let message = chat_input.Message("m1", "C1", None, author, "hello")
  let posted = chat_input.posted(message)
  let reacted = chat_input.reacted(message, author, "📚")
  let assert Ok(_) =
    check.value(posted, example_chat.input_type(), #(0, 0), fn(_) {
      Error("no references")
    })
  let assert Ok(_) =
    check.value(reacted, example_chat.input_type(), #(0, 0), fn(_) {
      Error("no references")
    })
  assert handler.run(channel.handle, posted, workspace.state)
    == Ok([
      work.Submit(
        None,
        option.Some("m1"),
        "hello",
        "[#general] Alice (message m1): hello",
      ),
    ])
  assert handler.run(channel.handle, reacted, workspace.state) == Ok([])
}

pub fn slack_default_handler_accepts_the_plugins_native_type_test() {
  let assert Ok(workspace) =
    config.load("test/fixtures/chat_workspace.eyg", test_helpers.state(), fn(_) {
      Error("no secrets")
    })
  let info = config.ChannelInfo("slack", "C1", "general", slack.input_type())
  let assert Ok(_) = config.channel(workspace, info)
}

pub fn discord_default_handler_accepts_the_plugins_native_type_test() {
  let assert Ok(workspace) =
    config.load("test/fixtures/chat_workspace.eyg", test_helpers.state(), fn(_) {
      Error("no secrets")
    })
  let info =
    config.ChannelInfo("discord", "C1", "general", discord.input_type())
  let assert Ok(_) = config.channel(workspace, info)
}
