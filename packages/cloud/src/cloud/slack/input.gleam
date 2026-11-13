//// Slack's history message fields and poll-derived reaction notifications.

import cloud/data
import cloud/slack/api/schema
import eyg/analysis/type_/isomorphic as t
import gleam/json
import gleam/list
import gleam/option.{type Option}

pub fn message_type() {
  t.record([
    #("ts", t.String),
    #("thread_ts", t.option(t.String)),
    #("reply_count", t.Integer),
    #("subtype", t.option(t.String)),
    #("deleted_ts", t.option(t.String)),
    #("user", t.option(t.String)),
    #("bot_id", t.option(t.String)),
    #("text", t.String),
    #("latest_reply", t.option(t.String)),
    #("data", t.String),
    #(
      "reactions",
      t.List(t.record([#("name", t.String), #("users", t.List(t.String))])),
    ),
  ])
}

pub fn event_types() {
  let fields = [
    #("channel", t.String),
    #("thread_ts", t.option(t.String)),
    #("message", message_type()),
    #("is_self", t.boolean),
  ]
  [
    #("SlackMessage", t.record(fields)),
    #(
      "SlackReaction",
      t.record([#("reaction", t.String), #("user", t.String), ..fields]),
    ),
  ]
}

pub fn input_type() {
  t.union(event_types())
}

pub fn message(raw: schema.Message) {
  data.record([
    #("ts", data.string(raw.ts)),
    #("thread_ts", data.option(raw.thread_ts, data.string)),
    #("reply_count", data.int(raw.reply_count)),
    #("subtype", data.option(raw.subtype, data.string)),
    #("deleted_ts", data.option(raw.deleted_ts, data.string)),
    #("user", data.option(raw.user, data.string)),
    #("bot_id", data.option(raw.bot_id, data.string)),
    #("text", data.string(raw.text)),
    #("latest_reply", data.option(raw.latest_reply, data.string)),
    #("data", data.string(json.to_string(raw.data))),
    #(
      "reactions",
      data.list(
        list.map(raw.reactions, fn(reaction) {
          data.record([
            #("name", data.string(reaction.name)),
            #("users", data.strings(reaction.users)),
          ])
        }),
      ),
    ),
  ])
}

fn fields(
  channel: String,
  thread: Option(String),
  raw: schema.Message,
  is_self: Bool,
) {
  [
    #("channel", data.string(channel)),
    #("thread_ts", data.option(thread, data.string)),
    #("message", message(raw)),
    #("is_self", data.bool(is_self)),
  ]
}

pub fn posted(
  channel: String,
  thread: Option(String),
  raw: schema.Message,
  is_self: Bool,
) {
  data.tagged(
    "SlackMessage",
    data.record(fields(channel, thread, raw, is_self)),
  )
}

pub fn reacted(
  channel: String,
  thread: Option(String),
  raw: schema.Message,
  user: String,
  reaction: String,
  is_self: Bool,
) {
  data.tagged(
    "SlackReaction",
    data.record([
      #("user", data.string(user)),
      #("reaction", data.string(reaction)),
      ..fields(channel, thread, raw, is_self)
    ]),
  )
}
