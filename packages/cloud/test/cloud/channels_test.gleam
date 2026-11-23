import cloud/apex/context.{Context}
import cloud/box
import cloud/channels
import cloud/helpers
import cloud/server
import gleam/dict
import gleam/erlang/process
import gleam/option.{Some}
import gleam/string

const write =
  "perform WriteFile({path: \"/a.txt\", contents: !string_to_binary(\"a\")})"

const read = "perform ReadFile({path: \"/a.txt\", offset: 0, limit: 10})"

pub fn channel_conversation_test() {
  // The channel's worker writes while the test reads, which one connection can not do.
  let context = helpers.pool_context()
  let server = server.start(process.new_subject())
  let context =
    Context(..context, llms: dict.from_list([#("test", server.llm(server))]))
  let name = helpers.unique("channels")
  let assert Ok(home) = box.create(context, Some(name))
  let assert Ok(channels) = channels.start(context, name, "test")
  let channel = helpers.unique("discord")
  let replies = process.new_subject()
  let reply = process.send(replies, _)

  // Messages go to the llm and code runs, in the same box and in the order they arrived.
  channels.deliver(channels, channel, channels.Text("run:" <> write), reply)
  channels.deliver(channels, channel, channels.Code(read), reply)
  channels.deliver(channels, channel, channels.Text("hello"), reply)
  let assert Ok(Ok(#(Ok("Ok({})"), []))) = process.receive(replies, 5000)
  let assert Ok(Ok(#(Ok(value), []))) = process.receive(replies, 5000)
  assert string.starts_with(value, "Ok(")
  // Code runs beside the chat, it has had two messages from the user.
  let assert Ok(Ok(#(Ok("hello #2"), []))) = process.receive(replies, 5000)

  // After a restart the channel talks to the same chat.
  let assert Ok(bound) = channels.chat(channels, channel)
  assert bound.box == home.id
  let assert Ok(restarted) = channels.start(context, name, "test")
  let assert Ok(again) = channels.chat(restarted, channel)
  assert bound.id == again.id
  let assert Ok(other) = channels.chat(restarted, helpers.unique("discord"))
  assert other.id != bound.id
}

pub fn the_box_must_exist_test() {
  let context = helpers.pool_context()
  let assert Error("there is no box named gone-box") =
    channels.start(context, "gone-box", "test")
}
