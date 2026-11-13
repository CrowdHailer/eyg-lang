//// Native Slack event comparisons used by the existing channel poller.

import cloud/channel
import cloud/slack/api/schema
import cloud/slack/input as slack_input
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}

pub const platform = "slack"

pub fn input_type() {
  slack_input.input_type()
}

/// The accounts the plugin posts as, used to mark native payloads with `is_self`.
pub type Me {
  Me(user: String, bot: String)
}

/// What has been reported about one message.
pub type Seen {
  Seen(reactions: List(#(String, String)), latest_reply: Option(String))
}

/// Compare messages, oldest first, with what has been seen.
/// Returns the events to report, the updated seen messages and threads,
/// as `#(thread_ts, since)`, with replies newer than `since` to fetch.
pub fn changes(
  channel_id: String,
  thread: Option(String),
  known: Dict(String, Seen),
  messages: List(schema.Message),
  me: Me,
) -> #(List(channel.Event), Dict(String, Seen), List(#(String, String))) {
  let #(events, known, threads) =
    list.fold(messages, #([], known, []), fn(acc, raw) {
      let #(events, known, threads) = acc
      case reportable(raw) {
        False -> acc
        True -> {
          let reply = reply_thread(thread, raw)
          let mine = raw.user == Some(me.user) || raw.bot_id == Some(me.bot)
          let reactions = reaction_pairs(raw.reactions)
          let previous = dict.get(known, raw.ts)
          let events = case previous {
            Error(Nil) -> [
              channel.Incoming(
                platform,
                channel_id,
                Some(option.unwrap(reply, raw.ts)),
                slack_input.posted(channel_id, reply, raw, mine),
              ),
              ..events
            ]
            Ok(seen) ->
              reactions
              |> list.filter(fn(pair) { !list.contains(seen.reactions, pair) })
              |> list.fold(events, fn(events, pair) {
                let #(emoji, user) = pair
                [
                  channel.Incoming(
                    platform,
                    channel_id,
                    Some(option.unwrap(reply, raw.ts)),
                    slack_input.reacted(
                      channel_id,
                      reply,
                      raw,
                      user,
                      emoji,
                      user == me.user,
                    ),
                  ),
                  ..events
                ]
              })
          }
          let seen_reply = case previous {
            Ok(seen) -> seen.latest_reply
            Error(Nil) -> None
          }
          let threads = case raw.latest_reply, thread {
            Some(latest), None if Some(latest) != seen_reply -> [
              #(raw.ts, option.unwrap(seen_reply, raw.ts)),
              ..threads
            ]
            _, _ -> threads
          }
          let seen = Seen(reactions:, latest_reply: raw.latest_reply)
          #(events, dict.insert(known, raw.ts, seen), threads)
        }
      }
    })
  #(list.reverse(events), known, list.reverse(threads))
}

/// Joins, leaves and other channel notices have a subtype, they are not messages.
fn reportable(message: schema.Message) {
  case message.subtype {
    None
    | Some("bot_message")
    | Some("thread_broadcast")
    | Some("file_share") -> True
    _ -> False
  }
}

fn reaction_pairs(reactions: List(schema.Reaction)) {
  list.flat_map(reactions, fn(reaction) {
    list.map(reaction.users, fn(user) { #(reaction.name, user) })
  })
}

fn reply_thread(thread, raw: schema.Message) {
  case thread, raw.thread_ts {
    Some(thread), _ -> Some(thread)
    None, Some(ts) if ts != raw.ts -> Some(ts)
    None, _ -> None
  }
}
