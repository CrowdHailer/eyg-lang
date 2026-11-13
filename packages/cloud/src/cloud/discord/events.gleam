//// Native Discord event comparisons used by the existing channel poller.

import cloud/channel
import cloud/discord/api/schema
import cloud/discord/input as discord_input
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const platform = "discord"

const discord_epoch = 1_420_070_400_000

pub fn input_type() {
  discord_input.input_type()
}

/// What has been seen in one channel or thread.
pub type Seen {
  Seen(
    /// The newest message id, later messages are new.
    newest: Option(String),
    /// Reaction counts per message, reactions are looked up when a count grows.
    counts: Dict(String, Dict(String, Int)),
    /// Users seen reacting per message, as `#(emoji, user)`.
    reacted: Dict(String, List(#(String, String))),
  )
}

pub fn unseen() -> Seen {
  Seen(newest: None, counts: dict.new(), reacted: dict.new())
}

/// A reaction whose count grew, the users who reacted must be looked up.
pub type Incoming {
  Incoming(channel: String, thread: Option(String), raw: schema.Post)
}

pub type Lookup {
  Lookup(message: Incoming, emoji: String, before: Int)
}

/// Thread names are at most 100 characters.
pub fn thread_name(content: String) -> String {
  case string.trim(content) |> string.split("\n") {
    [line, ..] if line != "" -> string.slice(line, 0, 80)
    _ -> "Conversation"
  }
}

/// Compare messages, oldest first, with what has been seen.
/// Returns the posted events, the reactions to look up and what has now been seen.
pub fn changes(
  channel_id: String,
  thread: Option(String),
  previous: Seen,
  messages: List(schema.Post),
  me: String,
  started: Int,
) -> #(List(channel.Event), List(Lookup), Seen) {
  // Cursor pagination and the recent reaction window can overlap.
  let messages =
    messages
    |> list.map(fn(message) { #(message.id, message) })
    |> dict.from_list
    |> dict.values
    |> list.sort(fn(a, b) { int.compare(snowflake(a.id), snowflake(b.id)) })
  let #(events, lookups, counts) =
    list.fold(messages, #([], [], dict.new()), fn(acc, raw) {
      let #(events, lookups, counts) = acc
      case raw.kind == 0 || raw.kind == 19 {
        False -> acc
        True -> {
          let message = Incoming(channel_id, thread, raw)
          let current = reaction_counts(raw.reactions)
          let new =
            is_newer(raw.id, previous.newest) && sent_at(raw.id) >= started
          let before = case dict.get(previous.counts, raw.id), new {
            Ok(before), _ -> before
            // Reactions already on a new message are reported.
            Error(Nil), True -> dict.new()
            // Reactions on history are not.
            Error(Nil), False -> current
          }
          let events = case new {
            True -> [
              channel.Incoming(
                platform,
                channel_id,
                Some(option.unwrap(thread, raw.id)),
                discord_input.posted(thread, raw, raw.author.id == me),
              ),
              ..events
            ]
            False -> events
          }
          let lookups =
            dict.fold(current, lookups, fn(lookups, emoji, count) {
              let was = dict.get(before, emoji) |> result.unwrap(0)
              case count > was {
                True -> [Lookup(message, emoji, was), ..lookups]
                False -> lookups
              }
            })
          #(events, lookups, dict.insert(counts, raw.id, current))
        }
      }
    })
  let newest =
    list.fold(messages, previous.newest, fn(newest, raw) {
      case is_newer(raw.id, newest) {
        True -> Some(raw.id)
        False -> newest
      }
    })
  // Only messages still in the window are kept.
  let reacted = dict.take(previous.reacted, dict.keys(counts))
  #(
    list.reverse(events),
    list.reverse(lookups),
    Seen(newest:, counts:, reacted:),
  )
}

/// Report the users not yet seen reacting with an emoji.
/// Discord does not say who reacted first, if users reacted before any were seen
/// they are all recorded without being reported.
pub fn reactions(
  seen: Seen,
  message: Incoming,
  emoji: String,
  before: Int,
  users: List(schema.User),
  me: String,
) -> #(List(channel.Event), Seen) {
  let known = dict.get(seen.reacted, message.raw.id) |> result.unwrap([])
  let quiet = before > 0 && !list.any(known, fn(pair) { pair.0 == emoji })
  let #(events, known) =
    list.fold(users, #([], known), fn(acc, user) {
      let #(events, known) = acc
      let pair = #(emoji, user.id)
      case list.contains(known, pair) {
        True -> acc
        False if quiet -> #(events, [pair, ..known])
        False -> {
          let value =
            discord_input.reacted(
              message.thread,
              message.raw,
              user,
              emoji,
              user.id == me,
            )
          #(
            [
              channel.Incoming(
                platform,
                message.channel,
                Some(option.unwrap(message.thread, message.raw.id)),
                value,
              ),
              ..events
            ],
            [pair, ..known],
          )
        }
      }
    })
  #(
    list.reverse(events),
    Seen(..seen, reacted: dict.insert(seen.reacted, message.raw.id, known)),
  )
}

fn reaction_counts(reactions: List(schema.Reaction)) {
  list.fold(reactions, dict.new(), fn(counts, reaction) {
    let schema.Reaction(emoji:, count:) = reaction
    let key = case emoji.id {
      Some(id) -> emoji.name <> ":" <> id
      None -> emoji.name
    }
    dict.insert(counts, key, count)
  })
}

fn is_newer(id: String, than: Option(String)) -> Bool {
  case than {
    None -> True
    Some(than) -> snowflake(id) > snowflake(than)
  }
}

fn snowflake(id) {
  int.parse(id) |> result.unwrap(0)
}

/// The unix time in milliseconds a snowflake was created.
pub fn sent_at(id: String) -> Int {
  int.bitwise_shift_right(snowflake(id), 22) + discord_epoch
}
