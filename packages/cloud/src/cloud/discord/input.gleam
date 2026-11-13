//// Discord's message, user and reaction fields, kept in their native shapes.

import cloud/data
import cloud/discord/api/schema
import eyg/analysis/type_/isomorphic as t
import gleam/list
import gleam/option.{type Option}

pub fn user_type() {
  t.record([#("id", t.String), #("username", t.String), #("bot", t.boolean)])
}

pub fn message_type() {
  t.record([
    #("id", t.String),
    #("channel_id", t.String),
    #("type", t.Integer),
    #("author", user_type()),
    #("webhook", t.boolean),
    #("content", t.String),
    #(
      "reactions",
      t.List(
        t.record([
          #(
            "emoji",
            t.record([#("id", t.option(t.String)), #("name", t.String)]),
          ),
          #("count", t.Integer),
        ]),
      ),
    ),
  ])
}

pub fn event_types() {
  let fields = [
    #("thread", t.option(t.String)),
    #("message", message_type()),
    #("is_self", t.boolean),
  ]
  [
    #("DiscordMessage", t.record(fields)),
    #(
      "DiscordReaction",
      t.record([#("emoji", t.String), #("user", user_type()), ..fields]),
    ),
  ]
}

pub fn input_type() {
  t.union(event_types())
}

pub fn user(raw: schema.User) {
  data.record([
    #("id", data.string(raw.id)),
    #("username", data.string(raw.username)),
    #("bot", data.bool(raw.bot)),
  ])
}

pub fn message(raw: schema.Post) {
  data.record([
    #("id", data.string(raw.id)),
    #("channel_id", data.string(raw.channel_id)),
    #("type", data.int(raw.kind)),
    #("author", user(raw.author)),
    #("webhook", data.bool(raw.webhook)),
    #("content", data.string(raw.content)),
    #(
      "reactions",
      data.list(
        list.map(raw.reactions, fn(reaction) {
          data.record([
            #(
              "emoji",
              data.record([
                #("id", data.option(reaction.emoji.id, data.string)),
                #("name", data.string(reaction.emoji.name)),
              ]),
            ),
            #("count", data.int(reaction.count)),
          ])
        }),
      ),
    ),
  ])
}

fn fields(thread: Option(String), raw: schema.Post, is_self: Bool) {
  [
    #("thread", data.option(thread, data.string)),
    #("message", message(raw)),
    #("is_self", data.bool(is_self)),
  ]
}

pub fn posted(thread: Option(String), raw: schema.Post, is_self: Bool) {
  data.tagged("DiscordMessage", data.record(fields(thread, raw, is_self)))
}

pub fn reacted(
  thread: Option(String),
  raw: schema.Post,
  by: schema.User,
  emoji: String,
  is_self: Bool,
) {
  data.tagged(
    "DiscordReaction",
    data.record([
      #("user", user(by)),
      #("emoji", data.string(emoji)),
      ..fields(thread, raw, is_self)
    ]),
  )
}
