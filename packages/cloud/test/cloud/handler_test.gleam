import cloud/config
import cloud/handler
import cloud/plugins/chat_input
import cloud/test_helpers
import cloud/work
import gleam/option.{None}

pub fn example_chat_native_values_and_default_handler_match_the_plugin_type_test() {
  let state = test_helpers.state()
  let assert Ok(workspace) =
    config.load("test/fixtures/chat_workspace.eyg", state, fn(_) {
      Error("no secrets")
    })
  let info =
    config.ChannelInfo("chat", "C1", "general", chat_input.input_type())
  let assert Ok(channel) = config.channel(workspace, info)
  let author = chat_input.Author("U1", "Alice", False)
  let message = chat_input.Message("m1", "C1", None, author, "hello")
  let posted = chat_input.posted(message)
  let reacted = chat_input.reacted(message, author, "📚")
  assert handler.run(channel.handle, posted, workspace.state)
    == Ok([
      work.Trigger(option.Some("m1")),
      work.Submit(
        None,
        option.Some("m1"),
        "hello",
        "[#general] Alice (message m1): hello",
      ),
    ])
  assert handler.run(channel.handle, reacted, workspace.state)
    == Ok([work.Trigger(option.Some("m1"))])
}
