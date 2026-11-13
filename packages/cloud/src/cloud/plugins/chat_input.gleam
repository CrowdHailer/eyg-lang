//// The example chat API's own event schema, without a shared message model.

import cloud/data
import eyg/analysis/type_/isomorphic as t
import gleam/option.{type Option}

pub type Author {
  Author(id: String, name: String, bot: Bool)
}

pub type Message {
  Message(
    id: String,
    channel: String,
    thread: Option(String),
    author: Author,
    text: String,
  )
}

pub fn author_type() {
  t.record([#("id", t.String), #("name", t.String), #("bot", t.boolean)])
}

pub fn message_type() {
  t.record([
    #("id", t.String),
    #("channel", t.String),
    #("thread", t.option(t.String)),
    #("author", author_type()),
    #("text", t.String),
  ])
}

pub fn event_types() {
  [
    #("ChatPosted", message_type()),
    #(
      "ChatReacted",
      t.record([
        #("message", message_type()),
        #("by", author_type()),
        #("emoji", t.String),
      ]),
    ),
  ]
}

pub fn input_type() {
  t.union(event_types())
}

pub fn author(value: Author) {
  data.record([
    #("id", data.string(value.id)),
    #("name", data.string(value.name)),
    #("bot", data.bool(value.bot)),
  ])
}

pub fn message(value: Message) {
  data.record([
    #("id", data.string(value.id)),
    #("channel", data.string(value.channel)),
    #("thread", data.option(value.thread, data.string)),
    #("author", author(value.author)),
    #("text", data.string(value.text)),
  ])
}

pub fn posted(value: Message) {
  data.tagged("ChatPosted", message(value))
}

pub fn reacted(value: Message, by: Author, emoji: String) {
  data.tagged(
    "ChatReacted",
    data.record([
      #("message", message(value)),
      #("by", author(by)),
      #("emoji", data.string(emoji)),
    ]),
  )
}
