//// Discord events currently supplied by the history poller.

import cloud/discord/api/schema
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/result

pub type Event {
  MessageCreate(id: String, channel_id: String, content: String)
}

pub fn from_message(message: schema.Message) -> Result(Event, String) {
  let decoder = decode.field("content", decode.string, decode.success)
  use content <- result.map(
    json.parse(json.to_string(message.data), decoder)
    |> result.replace_error("Invalid Discord message content"),
  )
  MessageCreate(message.id, message.channel_id, content)
}

pub fn type_() {
  t.record([
    #("channel_name", t.String),
    #(
      "event",
      t.union([
        #(
          "MessageCreate",
          t.record([
            #("id", t.String),
            #("channel_id", t.String),
            #("content", t.String),
          ]),
        ),
      ]),
    ),
  ])
}

pub fn to_eyg(channel_name: String, event: Event) -> v.Value(a, b) {
  let MessageCreate(id, channel_id, content) = event
  v.Record(
    dict.from_list([
      #("channel_name", v.String(channel_name)),
      #(
        "event",
        v.Tagged(
          "MessageCreate",
          v.Record(
            dict.from_list([
              #("id", v.String(id)),
              #("channel_id", v.String(channel_id)),
              #("content", v.String(content)),
            ]),
          ),
        ),
      ),
    ]),
  )
}
