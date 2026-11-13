//// Connections bring events from other services into a workspace.
////
//// Chat connections, `ExampleChat`, `Slack` and `Discord`, provide channels: messages reach agents
//// and `eyg` code blocks run with the channel shell.
//// Every other connection only reports events. Its events are logged and given to the
//// triggers of the channel the connection names, they never run code by themselves.
//// Connections are configured in `workspace.eyg`, see `guides/cloud/connections.md`.

import cloud/data
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/state
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type Source {
  /// The example chat app at `origin`.
  ExampleChat(origin: String)
  /// The Slack workspace the bot with `token` is installed in.
  Slack(token: String)
  /// The Discord server (guild) with id `guild` the bot with `token` is installed in.
  Discord(token: String, guild: String)
  /// Events of GitHub repositories, `owner/name`.
  /// Polled from the public events API every `every` seconds, 0 disables polling.
  /// Webhooks signed with `secret` are accepted at `/connections/<name>/webhook`.
  GitHub(repositories: List(String), secret: Option(String), every: Int)
  /// Posts by Bluesky accounts and in Bluesky feeds, given as feed generator `at://` URIs.
  Bsky(actors: List(String), feeds: List(String), every: Int)
  /// Items of RSS and Atom feeds.
  Rss(feeds: List(String), every: Int)
  /// Stories on Hacker News lists, `top`, `new`, `best`, `ask`, `show`.
  HackerNews(lists: List(String), every: Int)
  /// Stories on Lobsters lists, `hottest`, `newest` or `t/<tag>`.
  Lobsters(lists: List(String), every: Int)
}

pub type Connection {
  /// `channel` names the channel whose triggers receive the events of an event connection.
  Connection(name: String, source: Source, channel: Option(String))
}

/// An event reported by a connection that is not a chat.
/// The value is a plain EYG value, `summary` describes it in logs.
/// Events that happened before the connection started are reported with `live` false,
/// they are logged but run no triggers.
pub type Event {
  Event(
    connection: String,
    id: String,
    value: data.Value,
    summary: String,
    live: Bool,
  )
}

pub fn is_chat(source: Source) -> Bool {
  case source {
    ExampleChat(..) | Slack(..) | Discord(..) -> True
    _ -> False
  }
}

pub fn kind(source: Source) -> String {
  case source {
    ExampleChat(..) -> "ExampleChat"
    Slack(..) -> "Slack"
    Discord(..) -> "Discord"
    GitHub(..) -> "GitHub"
    Bsky(..) -> "Bsky"
    Rss(..) -> "Rss"
    HackerNews(..) -> "HackerNews"
    Lobsters(..) -> "Lobsters"
  }
}

type Reason =
  state.Reason(#(Int, Int))

/// Decode `{name, source, channel}`, `channel` is required for connections that are not chats.
pub fn decode(value: data.Value) -> Result(Connection, Reason) {
  use name <- result.try(cast.field("name", cast.as_string, value))
  use source <- result.try(cast.field("source", decode_source, value))
  use channel <- result.try(optional(value, "channel", cast.as_string))
  case is_chat(source), channel {
    False, None ->
      Error(break.IncorrectTerm("a channel for the events of " <> name, value))
    _, _ -> Ok(Connection(name:, source:, channel:))
  }
}

fn decode_source(value) {
  cast.as_variant(value, [
    #("ExampleChat", fn(c) {
      use origin <- result.map(cast.field("origin", cast.as_string, c))
      ExampleChat(origin)
    }),
    #("Slack", fn(c) {
      use token <- result.map(cast.field("token", cast.as_string, c))
      Slack(token)
    }),
    #("Discord", fn(c) {
      use token <- result.try(cast.field("token", cast.as_string, c))
      use guild <- result.map(cast.field("guild", cast.as_string, c))
      Discord(token:, guild:)
    }),
    #("GitHub", fn(c) {
      use repositories <- result.try(strings(c, "repositories"))
      use secret <- result.try(optional(c, "secret", cast.as_string))
      use every <- result.map(every(c, 60))
      GitHub(repositories:, secret:, every:)
    }),
    #("Bsky", fn(c) {
      use actors <- result.try(strings(c, "actors"))
      use feeds <- result.try(strings(c, "feeds"))
      use every <- result.map(every(c, 60))
      Bsky(actors:, feeds:, every:)
    }),
    #("Rss", fn(c) {
      use feeds <- result.try(strings(c, "feeds"))
      use every <- result.map(every(c, 300))
      Rss(feeds:, every:)
    }),
    #("HackerNews", fn(c) {
      use lists <- result.try(strings(c, "lists"))
      use every <- result.map(every(c, 120))
      HackerNews(lists: default_lists(lists, "top"), every:)
    }),
    #("Lobsters", fn(c) {
      use lists <- result.try(strings(c, "lists"))
      use every <- result.map(every(c, 120))
      Lobsters(lists: default_lists(lists, "newest"), every:)
    }),
  ])
}

fn default_lists(lists, default) {
  case lists {
    [] -> [default]
    lists -> lists
  }
}

/// An optional list of strings, missing is empty.
fn strings(value, field) {
  optional(value, field, cast.as_list_of(_, cast.as_string))
  |> result.map(option.unwrap(_, []))
}

/// Seconds between polls, missing is the default.
fn every(value, default) {
  optional(value, "every", cast.as_integer)
  |> result.map(option.unwrap(_, default))
}

fn optional(value, field, decoder) {
  case cast.field(field, Ok, value) {
    Ok(_) -> cast.field(field, decoder, value) |> result.map(Some)
    Error(_) -> Ok(None)
  }
}

/// Describe a connection as an EYG value, for the configuration API.
pub fn to_value(connection: Connection) -> data.Value {
  let Connection(name:, source:, channel:) = connection
  data.record([
    #("name", data.string(name)),
    #("kind", data.string(kind(source))),
    #("channel", data.option(channel, data.string)),
  ])
}

/// Keep the most recent events of each connection, newest first.
pub fn append_log(log: List(Event), event: Event, max: Int) -> List(Event) {
  [event, ..log] |> list.take(max)
}
