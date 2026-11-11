import argv
import cloud/slack/client
import cloud/slack/schema
import cloud/system
import envoy
import gleam/io
import gleam/json
import gleam/list
import gleam/string

pub fn main() {
  do_main(argv.load().arguments)
}

fn do_main(args) {
  case args {
    ["slack", "messages", channel] -> {
      let assert Ok(token) = envoy.get("SLACK_BOT_TOKEN")
      let context = client.Context(token, system.fetch)
      case client.conversations_history(context, channel)(identity) {
        Ok(messages) ->
          list.each(messages, fn(message) {
            io.println(json.to_string(message.data))
          })
        Error(reason) -> io.println_error(string.inspect(reason))
      }
    }
    ["slack", "channels"] -> {
      let assert Ok(token) = envoy.get("SLACK_BOT_TOKEN")
      let context = client.Context(token, system.fetch)
      case client.conversations_list(context)(identity) {
        Ok(channels) -> {
          let #(yes, no) =
            list.partition(channels, fn(channel) { channel.is_member })
          list.each(yes, fn(channel) {
            io.println(channel.name <> " - " <> "joined")
          })
          list.each(no, fn(channel) {
            io.println(channel.name <> " - " <> "not joined")
          })
        }
        Error(reason) -> io.println_error(string.inspect(reason))
      }
    }
    // check that slack access is available from the env variables.
    ["slack"] -> {
      let assert Ok(token) = envoy.get("SLACK_BOT_TOKEN")
      let context = client.Context(token, system.fetch)
      case client.auth_test(context)(identity) {
        Ok(schema.Identity(team:, ..)) -> io.println("access to team: " <> team)
        Error(reason) -> io.println_error(string.inspect(reason))
      }
    }
    _ ->
      io.println(
        "Usage: gleam dev slack | gleam dev slack channels | gleam dev slack messages <channel-id>",
      )
  }
}

fn identity(x) {
  x
}
