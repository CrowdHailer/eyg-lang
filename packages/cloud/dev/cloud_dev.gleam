import argv
import bucket/get_object
import bucket/list_objects
import cloud/blobs/blobs
import cloud/config
import cloud/data/migrations
import cloud/db/pool
import cloud/discord/api/client as discord
import cloud/old
import cloud/schedule
import cloud/schedules
import cloud/session
import cloud/slack/api/client
import cloud/slack/api/schema
import cloud/system
import envoy
import gleam/bit_array
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/string
import multiformats/cid/v1

pub fn main() {
  do_main(argv.load().arguments)
}

fn do_main(args) {
  case args {
    ["blobs", ..rest] -> {
      let assert Ok(config) = config.bucket()
      case rest {
        ["list"] -> {
          case blobs.list(config) {
            Ok(list_objects.ListObjectsResult(contents:, ..)) -> {
              list.each(contents, fn(object) {
                io.println(
                  object.key
                  <> " size: "
                  <> { int.to_string(object.size) |> string.pad_end(5, " ") }
                  <> " last_modified: "
                  <> object.last_modified,
                )
              })
            }
            Error(reason) -> io.println_error(string.inspect(reason))
          }
        }
        ["get", key] -> {
          case v1.from_string(key) {
            Ok(#(key, _)) ->
              case blobs.get(config, key) {
                Ok(get_object.Found(content)) ->
                  io.println(int.to_string(bit_array.byte_size(content)))
                Error(reason) -> io.println_error(string.inspect(reason))
                Ok(get_object.NotFound) -> io.println_error("not found")
              }
            Error(_) -> io.println_error("invalid key")
          }
        }
        _ -> io.println("unknown bucket action")
      }
    }
    ["cron", name] -> {
      let assert Ok(config) = config.bucket()
      let #(state, llm) = old.setup(config)
      let assert Ok(#(schedules, state)) = schedules.load(state)
      let assert Ok(runtime) = schedule.runtime(state)
      let assert Ok(sessions) =
        session.start(state.origin, llm, state.secrets, config)
      let #(outcome, _) =
        schedule.trigger_named(schedules, name, sessions.data, runtime)
      case outcome {
        Error(reason) -> io.println_error(reason)
        Ok(Nil) -> {
          let reply = process.new_subject()
          // An ordinary code message acts as a barrier after the agent turn.
          process.send(
            sessions.data,
            session.Message("Dev:cron", session.Code("{}"), fn(_) {
              process.send(reply, Nil)
            }),
          )
          case process.receive(reply, 300_000) {
            Ok(Nil) -> io.println("Finished cron action: " <> name)
            Error(_) ->
              panic as { "Timed out waiting for cron action: " <> name }
          }
        }
      }
    }
    ["migrate"] -> migrations.apply_all(db())
    ["rollback", count] -> {
      let assert Ok(count) = int.parse(count)
      migrations.rollback_n(db(), count)
    }
    ["discord", "messages", channel] -> {
      let assert Ok(token) = envoy.get("DISCORD_BOT_TOKEN")
      let context = discord.Context(token, system.fetch)
      case discord.channel_messages(context, channel)(identity) {
        Ok(messages) ->
          list.each(messages, fn(message) {
            io.println(json.to_string(message.data))
          })
        Error(reason) -> io.println_error(string.inspect(reason))
      }
    }
    ["discord", "channels"] -> {
      let assert Ok(token) = envoy.get("DISCORD_BOT_TOKEN")
      let assert Ok(guild) = envoy.get("DISCORD_GUILD_ID")
      let context = discord.Context(token, system.fetch)
      case discord.guild_channels(context, guild)(identity) {
        Ok(channels) ->
          list.each(channels, fn(channel) {
            io.println(channel.id <> " - " <> channel.name)
          })
        Error(reason) -> io.println_error(string.inspect(reason))
      }
    }
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
        "Usage: gleam dev blobs check | gleam dev blobs list | gleam dev blobs get <cid> | gleam dev cron <name> | gleam dev slack | gleam dev slack channels | gleam dev slack messages <channel-id> | gleam dev discord | gleam dev discord channels | gleam dev discord messages <channel-id>",
      )
  }
}

fn identity(x) {
  x
}

fn db() {
  let assert Ok(postgres) = config.postgres()
  let assert Ok(started) = pool.start(process.new_name("db_pool"), postgres)
  started.data
}
