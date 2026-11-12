import argv
import cloud/discord/api/client as discord
import cloud/slack/api/client
import cloud/slack/api/schema
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
    ["discord"] -> {
      let assert Ok(token) = envoy.get("DISCORD_BOT_TOKEN")
      let context = discord.Context(token, system.fetch)
      case discord.current_user(context)(identity) {
        Ok(user) -> io.println("access as bot: " <> user.username)
        Error(reason) -> io.println_error(string.inspect(reason))
      }
    }
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
        "Usage: gleam dev slack | gleam dev slack channels | gleam dev slack messages <channel-id> | gleam dev discord",
      )
  }
}

fn identity(x) {
  x
}
